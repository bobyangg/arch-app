import Observation
import SwiftUI

/// Your own profile, and every way it can change.
///
/// The You tab and the arrange screen hold this; everything below them — cards,
/// chips, the edit sheets — takes plain values and closures, so the whole tree
/// previews without a store.
@Observable
final class ProfileStore {

    var person: Person

    init(person: Person = MockData.you) {
        self.person = person
    }

    // MARK: Photos

    /// Something a write to the server could not do.
    ///
    /// Screens read this to say so. Nil almost always — a failed save is rare and
    /// is a thing to mention once, not a state to build a screen around.
    var lastError: ArchAPIError?

    /// Replace everything with what the server has.
    ///
    /// Used at launch and after a reconnection. The store keeps its identity so
    /// views already on screen refresh rather than being rebuilt underneath the
    /// reader.
    func adopt(_ person: Person) {
        self.person = person
        uploads.removeAll()
        rejections.removeAll()
        lastError = nil
    }

    /// Persist in the background, and remember if it did not work.
    ///
    /// The local change has already happened, so the reader sees their edit
    /// immediately. That is the right order for a profile edit — the alternative
    /// is a spinner on every keystroke — and it does mean a failure has to be
    /// reported afterwards rather than prevented.
    ///
    /// Does nothing in a design build, where there is nowhere to write.
    private func persist(_ work: @escaping () async throws -> Void) {
        guard ArchConfig.isConfigured else { return }
        Task { [weak self] in
            do {
                try await work()
                await MainActor.run { self?.lastError = nil }
            } catch let error as ArchAPIError {
                await MainActor.run { self?.lastError = error }
            } catch {
                await MainActor.run { self?.lastError = .transport }
            }
        }
    }

    var canAddPhoto: Bool { person.photos.count < Person.photoLimit }

    /// A profile needs a main photo, so the last one cannot be removed.
    var canRemovePhoto: Bool { person.photos.count > Person.requiredPhotos }

    /// Moves a photo to a position. Slot 0 is the main photo, so dragging a photo
    /// to the front is how you change what the roster shows — there is no separate
    /// "set as main" action to keep in sync with this one.
    func movePhoto(id: String, to destination: Int) {
        guard let source = person.photos.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(destination, 0), person.photos.count - 1)
        guard source != target else { return }
        let photo = person.photos.remove(at: source)
        person.photos.insert(photo, at: target)
        persist { [order = photoOrder] in
            try await ArchBackend.reorderPhotos(order)
        }
    }

    /// How many photos you could still add.
    var slotsLeft: Int { max(0, Person.photoLimit - person.photos.count) }

    /// Photos that are still on their way up, and ones that did not make it.
    ///
    /// Keyed by photo id rather than held on `Photo`, because uploading is
    /// something happening *to* a photo for a few seconds and not a property of
    /// the photograph itself.
    private(set) var uploads: [String: PhotoUpload] = [:]

    var failedUploads: Int { uploads.values.filter { $0 == .failed }.count }

    /// Photographs moderation would not take, and why.
    ///
    /// Kept apart from `uploads` deliberately. An upload is something happening to
    /// a photo for a few seconds; a rejection arrives hours or days later, against
    /// a photo that uploaded perfectly well. Folding the two together would mean a
    /// refusal looked like a network problem, and "Again" is exactly the wrong
    /// thing to offer somebody whose photograph was refused.
    private(set) var rejections: [String: PhotoRejection] = [:]

    var rejectedPhotos: Int { rejections.count }

    func reject(id: String, because reason: PhotoRejection) {
        rejections[id] = reason
        if let index = person.photos.firstIndex(where: { $0.id == id }) {
            person.photos[index].state = .rejected
        }
    }

    /// Adds picked photos in the order they were chosen.
    ///
    /// They appear in the grid immediately and upload behind you. Holding the grid
    /// hostage behind a spinner is how people end up staring at a progress bar
    /// wondering whether the app has frozen, and there is nothing here they need to
    /// wait for — the ordering and the cropping are already done.
    func addPhotos(_ picked: [PickedPhoto]) {
        for picked in picked.prefix(slotsLeft) {
            // A real uuid, because the server's column is one and the row is
            // written before the bytes are. The old "you-p" + six characters was
            // not a uuid and collided in shape with the seeded mock ids.
            let id = UUID().uuidString.lowercased()
            person.photos.append(
                Photo(id: id, toneIndex: picked.photo.toneIndex, state: .pending)
            )
            uploads[id] = .uploading
        }
    }

    func finishUpload(id: String) { uploads[id] = nil }
    func failUpload(id: String) { uploads[id] = .failed }
    func retryUpload(id: String) { uploads[id] = .uploading }

    func removePhoto(id: String) {
        guard canRemovePhoto else { return }
        person.photos.removeAll { $0.id == id }
        uploads[id] = nil
        rejections[id] = nil
        persist { try await ArchBackend.removePhoto(id: id) }
    }

    /// The order, as the whole list rather than as a move.
    ///
    /// `reorder_photos` on the server takes the same shape for the same reason:
    /// positions are unique per account, so writing them one at a time collides
    /// with itself, and a whole order can be re-sent after a dropped connection
    /// without working out what landed.
    var photoOrder: [String] { person.photos.map(\.id) }

    // MARK: Answers

    func moveAnswer(id: String, to destination: Int) {
        guard let source = person.prompts.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(destination, 0), person.prompts.count - 1)
        guard source != target else { return }
        let prompt = person.prompts.remove(at: source)
        person.prompts.insert(prompt, at: target)
        persist { [prompts = person.prompts] in
            try await ArchBackend.savePrompts(prompts)
        }
    }

    func updateAnswer(id: String, to text: String) {
        guard let index = person.prompts.firstIndex(where: { $0.id == id }) else { return }
        let existing = person.prompts[index]
        person.prompts[index] = Prompt(id: existing.id, question: existing.question, answer: text)
        persist { [prompts = person.prompts] in
            try await ArchBackend.savePrompts(prompts)
        }
    }

    /// Question and answer move together, because changing one without the other
    /// leaves a non sequitur on the profile.
    func updatePrompt(id: String, question: String, answer: String) {
        guard let index = person.prompts.firstIndex(where: { $0.id == id }) else { return }
        person.prompts[index] = Prompt(id: id, question: question, answer: answer)
        persist { [prompts = person.prompts] in
            try await ArchBackend.savePrompts(prompts)
        }
    }

    /// The questions the other slots are using, so a picker can mark them.
    func questionsTaken(excluding id: String) -> [String] {
        person.prompts.filter { $0.id != id }.map(\.question)
    }

    // MARK: Interests

    /// Takes the raw strings from the editor. Blanks are dropped rather than
    /// stored as empty chips, and everything is clipped to the limit.
    func setInterests(_ texts: [String]) {
        person.interests = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Person.requiredInterests)
            .enumerated()
            .map { index, text in
                Interest(id: "you-i\(index + 1)", text: String(text.prefix(Interest.characterLimit)))
            }
        persist { [interests = person.interests] in
            try await ArchBackend.saveInterests(interests)
        }
    }

    // MARK: Details

    /// Set from the device, never typed. Kept apart from `updateDetails` because
    /// it is not something anybody edits — see `Person.coordinate`.
    func setCoordinate(_ coordinate: Coordinate?) {
        person.coordinate = coordinate
    }

    func updateDetails(_ details: PersonDetails) {
        person.name = details.name
        person.age = details.age
        person.gender = details.gender
        person.pronouns = details.pronouns
        person.place = details.place
        person.height = details.height
        person.work = details.work
        persist { try await ArchBackend.saveDetails(details) }
    }
}

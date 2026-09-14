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
    /// The task is `@MainActor` rather than three `MainActor.run` closures inside a
    /// plain one. `[weak self]` captures a *mutable* optional, and reading it from
    /// a closure nested inside the task is a data race the compiler will refuse
    /// outright in Swift 6 -- it warns about it today. Isolating the whole
    /// continuation instead means the assignment is a direct main-actor access with
    /// no inner closure to smuggle `self` into. `work()` is nonisolated and async,
    /// so awaiting it still leaves the main actor for the duration of the request.
    private func persist(_ work: @escaping () async throws -> Void) {
        guard ArchConfig.isConfigured else { return }
        Task { @MainActor [weak self] in
            do {
                try await work()
                self?.lastError = nil
            } catch let error as ArchAPIError {
                self?.lastError = error
            } catch {
                self?.lastError = .transport
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
    ///
    /// Read off the photographs rather than stored beside them. It was a separate
    /// dictionary, which meant the server's answer had to be copied into a second
    /// place on every load — and it never was, so a refusal that arrived from the
    /// server was invisible no matter what the server said.
    var rejections: [String: PhotoRejection] {
        Dictionary(uniqueKeysWithValues: person.photos.compactMap { photo in
            photo.rejection.map { (photo.id, $0) }
        })
    }

    var rejectedPhotos: Int { rejections.count }

    /// Whether a second look has been asked for, per photograph. One each.
    private(set) var reviewsAsked: Set<String> = []

    func reject(id: String, because reason: PhotoRejection) {
        guard let index = person.photos.firstIndex(where: { $0.id == id }) else { return }
        person.photos[index].state = .rejected
        person.photos[index].rejection = reason
    }

    /// Asks a person to look at a refused photograph again.
    ///
    /// Deliberately does not clear the refusal. Most photographs sent back stay
    /// back, and a screen that cleared it on asking would be showing somebody their
    /// photo restored before anybody had looked.
    func askForReview(id: String, note: String) {
        reviewsAsked.insert(id)
        persist { try await ArchBackend.askForPhotoReview(id: id, note: note) }
    }

    /// Adds picked photos in the order they were chosen.
    ///
    /// They appear in the grid immediately and upload behind you. Holding the grid
    /// hostage behind a spinner is how people end up staring at a progress bar
    /// wondering whether the app has frozen, and there is nothing here they need to
    /// wait for — the ordering and the cropping are already done.
    func addPhotos(_ picked: [PickedPhoto]) {
        for item in picked.prefix(slotsLeft) {
            // A real uuid, because the server's column is one and the row is
            // written before the bytes are. The old "you-p" + six characters was
            // not a uuid and collided in shape with the seeded mock ids.
            let id = UUID().uuidString.lowercased()
            let position = person.photos.count
            person.photos.append(
                Photo(id: id,
                      toneIndex: item.photo.toneIndex,
                      // Shown from memory until the upload finishes and a signed
                      // URL exists. Without this the new tile is a flat tone for as
                      // long as the network takes, which reads as a failure.
                      url: nil,
                      state: .pending)
            )
            uploads[id] = .uploading
            upload(id: id, position: position, item: item)
        }
    }

    /// Render the crop and send it.
    ///
    /// The rendering is off the main actor: a 1080-square draw from a 12-megapixel
    /// original is tens of milliseconds, which is a visible stutter in a grid the
    /// reader is still looking at.
    private func upload(id: String, position: Int, item: PickedPhoto) {
        guard ArchConfig.isConfigured else { return }
        // `@MainActor` on the task for the same reason as in `persist` above. The
        // rendering still happens off it: `Task.detached` below takes no isolation
        // from here, which is the whole point of it.
        Task { @MainActor [weak self] in
            // Hoisted out of the `guard` rather than written inline. A trailing
            // closure is not allowed in a control-flow condition -- Swift reads the
            // `{` as the start of the guard body, and the error it gives is about
            // a missing `else` several lines away from the cause.
            let rendered = Task.detached(priority: .userInitiated) {
                PhotoExport.jpeg(from: item.photo, crop: item.crop)
            }
            guard let jpeg = await rendered.value else {
                self?.failUpload(id: id)
                return
            }
            do {
                try await ArchBackend.addPhoto(id: id, position: position, jpeg: jpeg)
                self?.finishUpload(id: id)
            } catch {
                // The row stays, which is what lets the grid offer "Again" -- and
                // what makes a lost upload survive the app being closed.
                self?.failUpload(id: id)
            }
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

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
    }

    /// A design build has no photo picker, so a new photo is the next quarry tone.
    func addPhoto() {
        guard canAddPhoto else { return }
        person.photos.append(
            Photo(
                id: "you-p\(UUID().uuidString.prefix(6))",
                toneIndex: person.photos.count % ArchColor.materials.count
            )
        )
    }

    func removePhoto(id: String) {
        guard canRemovePhoto else { return }
        person.photos.removeAll { $0.id == id }
    }

    // MARK: Answers

    func moveAnswer(id: String, to destination: Int) {
        guard let source = person.prompts.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(destination, 0), person.prompts.count - 1)
        guard source != target else { return }
        let prompt = person.prompts.remove(at: source)
        person.prompts.insert(prompt, at: target)
    }

    /// Only the answer changes. Choosing a different question is a later job.
    func updateAnswer(id: String, to text: String) {
        guard let index = person.prompts.firstIndex(where: { $0.id == id }) else { return }
        let existing = person.prompts[index]
        person.prompts[index] = Prompt(id: existing.id, question: existing.question, answer: text)
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
    }

    // MARK: Details

    func updateDetails(
        name: String,
        age: Int,
        neighbourhood: String,
        city: String,
        height: String,
        work: String
    ) {
        person.name = name
        person.age = age
        person.neighbourhood = neighbourhood
        person.city = city
        person.height = height
        person.work = work
    }
}

import Observation
import SwiftUI

/// Everything onboarding collects, and the rules for when you may move on.
///
/// The profile being built is a real `ProfileStore` started from `Person.empty`, so
/// onboarding uses exactly the same mutators the You tab does — `addPhoto`,
/// `updateAnswer`, `setInterests`, `updateDetails` — and finishing is just handing
/// that object to the app.
@Observable
final class OnboardingStore {

    /// There is no phone step.
    ///
    /// There was one, behind a flag, and the flag was off: an account is tied to
    /// an Apple ID and a device, which is what Safety says and what actually
    /// happens. Sign in with Apple replaced the number, `delete_account` keeps the
    /// Apple id claimed so a removed account cannot start again, and DeviceCheck
    /// carries the rest. A number would have verified nothing that was not already
    /// verified, so the two screens and the change-number sheet are gone rather
    /// than parked.
    enum Step: Int, CaseIterable {
        case identity
        case about
        case seeking
        case photos
        case answers
        case interests
        case questions
        case notifications
    }

    /// The steps, in order.
    ///
    /// Kept as a list rather than read off `Step.rawValue`, because everything
    /// that used to do arithmetic on the raw value walks this instead — so a step
    /// added or removed cannot leave the progress rule counting a screen nobody
    /// sees or the back button reaching one.
    static var steps: [Step] { Step.allCases }

    static var firstStep: Step { steps.first ?? .identity }

    /// Built up as you go, then handed to `RootTabView`.
    let profile = ProfileStore(person: .empty)

    var step: Step = OnboardingStore.firstStep

    var name = ""
    /// From Apple, and only ever on the first authorization. Never shown to
    /// anybody — it is here so account notices have somewhere to go.
    var email = ""
    /// Apple's stable id for this person and this app. The account key.
    var appleUserID = ""
    var ageText = ""
    /// Picked from the library, so it carries a position as well as its name.
    var place: Place?
    /// What iOS has said, and the square it gave back. The precise fix never
    /// leaves the moment it arrives in.
    var locationPermission: LocationPermission = .notAsked
    var coordinate: Coordinate?
    var height = ""
    var work = ""
    var genderDraft: Gender?
    var pronounsDraft = ""

    /// Who you want to meet. A set, because "men and non-binary people" is a
    /// perfectly ordinary answer and a single choice cannot hold it.
    var seekingDrafts: Set<Gender> = []

    var interestDrafts = ["", "", ""]

    /// nil while the questionnaire intro is showing.
    var questionIndex: Int?
    var questionnaireAnswers: [String: String] = [:]

    var allowsNotifications = false

    private var person: Person { profile.person }

    // MARK: The progress rule

    /// Inside the questionnaire the rule switches to the questions, so there is
    /// only ever one rule on screen rather than two competing ones.
    var ruleTotal: Int {
        questionIndex == nil ? Self.steps.count : Questionnaire.count
    }

    var ruleCurrent: Int {
        if let questionIndex { return questionIndex + 1 }
        return (Self.steps.firstIndex(of: step) ?? 0) + 1
    }

    // MARK: Gating

    var canContinue: Bool {
        switch step {
        case .identity:
            return !name.isBlank
        case .about:
            return Int(ageText) != nil && place != nil
                && !height.isBlank && !work.isBlank
                && genderDraft != nil
        case .seeking:
            // Nobody is a valid preference for exactly nobody.
            return !seekingDrafts.isEmpty
        case .photos:
            return photoShortfall == 0
        case .answers:
            return person.answeredPrompts.count >= Person.requiredPrompts
        case .interests:
            return interestDrafts.filter { !$0.isBlank }.count >= Person.requiredInterests
        case .questions:
            // The intro's "Start" is always available; the questions themselves
            // advance on choosing an option and exit the step on the last one.
            return true
        case .notifications:
            return true
        }
    }

    /// A photo that did not upload is not a photo yet, so it does not count
    /// towards the four. Letting it count would walk somebody out of onboarding
    /// with three photographs on their profile and a fourth that never arrived.
    var photoShortfall: Int {
        max(0, Person.requiredPhotos - (person.photos.count - profile.failedUploads))
    }

    /// Names the gap rather than leaving a dead button to be guessed at.
    var photoShortfallText: String {
        if profile.failedUploads > 0 {
            return profile.failedUploads == 1
                ? "One photo did not upload. Tap it to try again."
                : "\(ArchCopy.capitalisedWord(profile.failedUploads)) photos did not upload. Tap them to try again."
        }
        switch photoShortfall {
        case 0: return "You can add \(ArchCopy.word(Person.photoLimit - person.photos.count)) more."
        case 1: return "One more photo."
        default: return "\(ArchCopy.capitalisedWord(photoShortfall)) more photos."
        }
    }

    // MARK: Moving

    var canGoBack: Bool {
        step != Self.firstStep
    }

    func advance() {
        switch step {
        case .about:
            commitDetails()
            step = .seeking
        case .interests:
            profile.setInterests(interestDrafts)
            step = .questions
        case .notifications:
            break
        default:
            if let next = Self.step(after: step) { step = next }
        }
    }

    private static func step(after current: Step) -> Step? {
        guard let index = steps.firstIndex(of: current), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    private static func step(before current: Step) -> Step? {
        guard let index = steps.firstIndex(of: current), index > 0 else { return nil }
        return steps[index - 1]
    }

    func back() {
        if step == .questions, let index = questionIndex {
            questionIndex = index == 0 ? nil : index - 1
            return
        }
        if let previous = Self.step(before: step) { step = previous }
    }

    // MARK: Questionnaire

    func startQuestions() { questionIndex = 0 }

    func answer(_ question: QuestionnaireQuestion, with option: String) {
        questionnaireAnswers[question.id] = option
    }

    /// Advances, or leaves the questionnaire entirely when the last one is done.
    func advanceQuestion() {
        guard let index = questionIndex else { return }
        if index + 1 < Questionnaire.count {
            questionIndex = index + 1
        } else {
            questionIndex = nil
            step = .notifications
        }
    }

    // MARK: Details

    /// A location, taken once and immediately rounded.
    ///
    /// The nearest place fills the profile chip, because a geocoder saying
    /// "Bedford-Stuyvesant" is not what somebody who writes "Bed-Stuy" wants under
    /// their name — the picker is still there to correct it.
    /// What Apple handed over at the front door.
    ///
    /// The name is a starting point rather than an answer — what is on an Apple ID
    /// is not always what somebody wants a stranger reading — so it fills the field
    /// and stays editable.
    func apply(_ identity: AppleIdentity) {
        appleUserID = identity.userID
        if let name = identity.name, !name.isBlank { self.name = name }
        if let email = identity.email { self.email = email }
    }

    /// **The words are handed in rather than looked up here.** They come from
    /// the device's geocoder, which knows the whole of both countries;
    /// `PlaceLibrary.nearest` used to do it and searched thirty-two New York
    /// neighbourhoods, so a fix anywhere else was confidently wrong.
    ///
    /// A nil `found` is the honest outcome when the geocoder could not answer.
    /// The position is still kept — it is the thing the distance filter reads,
    /// and it is right — and the picker stays open for a name to be chosen.
    ///
    /// **It replaces whatever was there, and `if place == nil` was the bug.**
    /// Somebody who had picked Toronto from the list and then tapped "Use my
    /// location" in Chicago kept Toronto: the coordinate moved to Chicago and
    /// the name did not, which is worse than either on its own — the chip said
    /// one city and the distance filter used another. Tapping that button is an
    /// explicit instruction, and the only reason to guard it was to avoid
    /// overwriting a choice nobody had made yet.
    func useDeviceLocation(_ fix: Coordinate, place found: Place?) {
        locationPermission = .granted
        coordinate = fix.coarsened
        if let found { place = found }
    }

    func refuseDeviceLocation() {
        locationPermission = .denied
    }

    private func commitDetails() {
        profile.setCoordinate(coordinate)
        profile.updateDetails(
            PersonDetails(
                name: name.trimmed,
                age: Int(ageText) ?? 0,
                gender: genderDraft,
                pronouns: pronounsDraft.trimmed,
                place: place,
                height: height.trimmed,
                work: work.trimmed
            )
        )
    }
}

extension OnboardingStore {
    /// Builds a configured store in a single expression, for previews.
    static func configured(_ configure: (OnboardingStore) -> Void) -> OnboardingStore {
        let store = OnboardingStore()
        configure(store)
        return store
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
}

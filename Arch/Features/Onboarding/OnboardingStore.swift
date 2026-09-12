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

    enum Step: Int, CaseIterable {
        case verify
        case identity
        case about
        case seeking
        case photos
        case answers
        case interests
        case questions
        case notifications
    }

    /// Phone verification, on or off.
    ///
    /// Off while there is no backend to verify against and no SMS to receive, so
    /// the flow can be walked end to end without inventing a code. **Nothing is
    /// deleted**: `OnboardingPhone` and `OnboardingCode` are untouched, their
    /// previews still build them, and setting this back to `true` puts both
    /// screens back at the front of the flow exactly as they were.
    ///
    /// The design still says every account has a verified number — Safety says so
    /// in as many words — because that is still the intent. This is a switch for
    /// working on the rest, not a change of mind.
    static let isVerificationOn = false

    /// The steps actually in the flow, in order.
    ///
    /// Everything that used to do arithmetic on `Step.rawValue` now walks this
    /// instead, so switching a step off cannot leave the rule counting a screen
    /// nobody sees or the back button reaching one.
    static var steps: [Step] {
        isVerificationOn ? Step.allCases : Step.allCases.filter { $0 != .verify }
    }

    static var firstStep: Step { steps.first ?? .identity }

    /// Built up as you go, then handed to `RootTabView`.
    let profile = ProfileStore(person: .empty)

    var step: Step = OnboardingStore.firstStep

    /// Verification is two screens under one step: the number, then the code.
    var hasSentCode = false
    var phone = ""
    var code = ""

    var name = ""
    var email = ""
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
        case .verify:
            return hasSentCode ? code.count == 6 : phone.filter(\.isNumber).count >= 7
        case .identity:
            return !name.isBlank && email.contains("@") && !email.hasSuffix("@")
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
        step != Self.firstStep || hasSentCode
    }

    func advance() {
        switch step {
        case .verify where !hasSentCode:
            hasSentCode = true
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
        if step == .verify {
            hasSentCode = false
            code = ""
            return
        }
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
    func useDeviceLocation(_ fix: Coordinate) {
        locationPermission = .granted
        coordinate = fix.coarsened
        if place == nil { place = PlaceLibrary.nearest(to: fix) }
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

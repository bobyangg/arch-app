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

    /// Built up as you go, then handed to `RootTabView`.
    let profile = ProfileStore(person: .empty)

    var step: Step = .verify

    /// Verification is two screens under one step: the number, then the code.
    var hasSentCode = false
    var phone = ""
    var code = ""

    var name = ""
    var email = ""
    var ageText = ""
    var neighbourhood = ""
    var city = ""
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
        questionIndex == nil ? Step.allCases.count : Questionnaire.count
    }

    var ruleCurrent: Int {
        if let questionIndex { return questionIndex + 1 }
        return step.rawValue + 1
    }

    // MARK: Gating

    var canContinue: Bool {
        switch step {
        case .verify:
            return hasSentCode ? code.count == 6 : phone.filter(\.isNumber).count >= 7
        case .identity:
            return !name.isBlank && email.contains("@") && !email.hasSuffix("@")
        case .about:
            return Int(ageText) != nil && !neighbourhood.isBlank
                && !city.isBlank && !height.isBlank && !work.isBlank
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
        step != .verify || hasSentCode
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
            if let next = Step(rawValue: step.rawValue + 1) { step = next }
        }
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
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
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

    private func commitDetails() {
        profile.updateDetails(
            PersonDetails(
                name: name.trimmed,
                age: Int(ageText) ?? 0,
                gender: genderDraft,
                pronouns: pronounsDraft.trimmed,
                neighbourhood: neighbourhood.trimmed,
                city: city.trimmed,
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

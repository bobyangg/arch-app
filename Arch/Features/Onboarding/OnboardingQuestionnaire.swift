import SwiftUI

/// The compatibility questions: an intro, then one question per screen.
///
/// **The intro is where the honesty has to live.** A compatibility questionnaire is
/// the single most likely place for this app to grow the match percentages the rest
/// of the design has avoided, so the screen says plainly that the answers are
/// private and do not add up to a score — before it starts asking.
struct OnboardingQuestionnaire: View {
    let store: OnboardingStore
    /// Whether Back on the *first* question may leave the questions entirely.
    ///
    /// In onboarding it goes to the intro, which is a real screen you can come
    /// back from. In Settings leaving is *finishing* -- `questionIndex == nil` is
    /// the signal that screen watches for to write the answers -- so there the
    /// control is hidden on the first question rather than offered as a way to
    /// end something you opened in order to edit.
    var backLeavesQuestions: Bool = true

    var body: some View {
        if let index = store.questionIndex, index < Questionnaire.count {
            question(Questionnaire.questions[index])
        } else {
            intro
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "A few questions",
                detail: "These are how Arch decides who reaches your five."
            )

            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                point("Your answers are not on your profile.")
                point("Nobody else sees them.")
                point("They do not add up to a score, and Arch will never show you a percentage.")
            }

            Text("\(Questionnaire.count) questions, about two minutes. There is no wrong answer to any of them, and you can change what you said later in Settings.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func point(_ text: String) -> some View {
        Text(text)
            .archText(.body)
            .foregroundStyle(ArchColor.limestone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func question(_ question: QuestionnaireQuestion) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            Text(question.text)
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: ArchSpacing.xs) {
                ForEach(question.options, id: \.self) { option in
                    OptionRow(
                        text: option,
                        isSelected: store.questionnaireAnswers[question.id] == option
                    ) {
                        choose(option, for: question)
                    }
                }
            }

            // **Said in words, next to the thing it undoes.** There has always
            // been a chevron in the top bar and it has always worked, but a
            // questionnaire that advances by itself 260ms after a tap is exactly
            // where somebody picks the wrong option -- and at that moment they
            // are looking at the answers, not at the corner of the screen. The
            // same control the Settings version of this screen already had.
            if canGoBack {
                ArchTextButton(title: "Back a question") {
                    withAnimation(ArchMotion.standard) { store.back() }
                }
            }
        }
    }

    private var canGoBack: Bool {
        guard let index = store.questionIndex else { return false }
        return index > 0 || backLeavesQuestions
    }

    /// Marks the choice, then moves on after a beat.
    ///
    /// Auto-advance is in tension with an app that is deliberately unhurried — but
    /// twenty questions with a Next button each is a form, and forms are where
    /// people quit. The pause is long enough to see what you picked, and Back is
    /// always in the top bar.
    private func choose(_ option: String, for question: QuestionnaireQuestion) {
        store.answer(question, with: option)
        let tapped = store.questionIndex
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            // Only if this is still the question that was tapped. Two taps used
            // to queue two moves, and the second one stepped past the next
            // question without it being answered.
            guard store.questionIndex == tapped else { return }
            withAnimation(ArchMotion.standard) {
                store.advanceQuestion()
            }
        }
    }
}

/// One answer option. Selected is marked by a border rather than by `lamp` — the
/// accent means "this is the action", and here every row is equally an action.
struct OptionRow: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ArchSpacing.m)
            .padding(.vertical, ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(isSelected ? ArchColor.stoneRaised : ArchColor.stone)
            )
            .archSelected(isSelected, radius: ArchRadius.control, tint: ArchColor.limestone)
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Questionnaire intro") {
    OnboardingQuestionnaire(store: OnboardingStore())
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("A question") {
    OnboardingQuestionnaire(store: .configured { $0.questionIndex = 0 })
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

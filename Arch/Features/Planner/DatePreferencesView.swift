import SwiftUI

/// What the Date planner says before its first plan: what it does, the five
/// questions it wants answered first, and what happens to the answers.
///
/// One view in two places -- the planner tab, the first time it is opened, and
/// the popup that introduces the planner straight after onboarding -- so the two
/// can never describe it differently.
///
/// **The privacy line is exact, and narrower than the questionnaire's.** The
/// onboarding answers are seen by nobody, ever. These are planned around on the
/// phone of anybody you are talking to, because a plan for two has to know what
/// both people said; so this says they are not on your profile and are never
/// shown, not that nobody could ever read them. See `backend/029`.
struct PlannerGetStarted: View {
    /// Questions answered on a run you backed out of, and kept: the button
    /// says Continue, and how far you got.
    var answered: Int = 0
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.l) {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("Plan dates you would both enjoy")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                point("Five quick questions about your ideal date. Multiple choice, under a minute.")
                point("Arch plans dates based on both your preferences.")
                point("Your answers are not on your profile, and Arch never shows them to anybody. You can change them from the planner.")
            }

            VStack(spacing: ArchSpacing.xs) {
                ArchButton(title: answered > 0 ? "Continue" : "Get started", action: onStart)
                    .accessibilityIdentifier("planner.getStarted")
                if answered > 0 {
                    Text("\(answered) of \(DatePreferences.questions.count) answered. Your answers are kept.")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                }
            }
        }
    }

    /// One sentence. The numerals that used to sit beside these were cut to
    /// keep the screen short.
    private func point(_ text: String) -> some View {
        Text(text)
            .archText(.body)
            .foregroundStyle(ArchColor.limestone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The five questions, one to a screen.
///
/// Built the way the onboarding questionnaire is -- the same option rows, the
/// same step rule, the same short pause before moving on -- because they are
/// the same kind of thing and should feel like it.
struct DatePreferenceQuestions: View {
    /// Which question is showing. Set to nil to leave.
    @Binding var index: Int?
    /// One answer per question, as an option index.
    @Binding var draft: [Int?]
    let onFinish: (DatePreferences) -> Void

    var body: some View {
        if let index, index < DatePreferences.questions.count {
            let question = DatePreferences.questions[index]
            VStack(alignment: .leading, spacing: ArchSpacing.xl) {
                VStack(alignment: .leading, spacing: ArchSpacing.s) {
                    StepRule(total: DatePreferences.questions.count, current: index + 1)
                    Text("\(index + 1) of \(DatePreferences.questions.count)")
                        .archText(.caption)
                        .foregroundStyle(ArchColor.mortar)
                }

                Text(question.text)
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: ArchSpacing.xs) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { option, text in
                        OptionRow(text: text, isSelected: draft[index] == option) {
                            choose(option, at: index)
                        }
                        .accessibilityIdentifier("planner.option.\(option)")
                    }
                }

                ArchTextButton(title: index == 0 ? "Back" : "Back a question") {
                    withAnimation(ArchMotion.standard) { self.index = index == 0 ? nil : index - 1 }
                }
                .accessibilityIdentifier("planner.questionBack")
            }
        }
    }

    /// Marks the choice, then moves on after a beat -- or, on the last
    /// question, finishes. Only if this is still the question that was tapped,
    /// so two quick taps cannot skip one.
    private func choose(_ option: Int, at tapped: Int) {
        draft[tapped] = option
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard index == tapped else { return }
            withAnimation(ArchMotion.standard) {
                if tapped + 1 < DatePreferences.questions.count {
                    index = tapped + 1
                } else if let preferences = DatePreferences(answers: draft) {
                    onFinish(preferences)
                    index = nil
                } else {
                    // One was skipped with Back and never answered: go to it.
                    index = draft.firstIndex { $0 == nil }
                }
            }
        }
    }
}

#Preview("Get started") {
    PlannerGetStarted(onStart: {})
        .padding(ArchSpacing.screenMargin)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

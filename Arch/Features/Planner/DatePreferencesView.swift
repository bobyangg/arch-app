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
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.l) {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("Plan dates you would both enjoy")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pick somebody you are talking to, and the planner lays out an afternoon or an evening: three stops, chosen from what you both like, about halfway between you.")
                    .archText(.body)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                point("5", "Five quick questions about your ideal date. Multiple choice, under a minute.")
                point("2", "Plans fit you both. If either of you does not drink, or wants to keep it walkable, so does every plan.")
                point("0", "Your answers are not on your profile, and Arch never shows them to anybody. You can change them from the planner.")
            }

            ArchButton(title: "Get started", action: onStart)
                .accessibilityIdentifier("planner.getStarted")
        }
    }

    /// A numeral and a sentence. The numerals are the screen's whole argument
    /// -- five questions, two of you, nothing shown -- set where the eye starts.
    private func point(_ figure: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ArchSpacing.s) {
            Text(figure)
                .archText(.titleM)
                .foregroundStyle(ArchColor.lamp)
                .frame(width: 28, alignment: .leading)
                .accessibilityHidden(true)
            Text(text)
                .archText(.body)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The Date planner, introduced once, straight after onboarding.
///
/// A sheet rather than a screen in the onboarding flow: onboarding is already
/// eight steps, and these questions are about dates with people you have not
/// met yet. Here they are one tap away and entirely optional -- "Not now" leaves
/// them waiting in the planner tab, where they are asked again on first visit.
struct PlannerIntroSheet: View {
    let onStart: () -> Void
    let onLater: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                Text("New in Arch")
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.top, ArchSpacing.xl)

                PlannerGetStarted(onStart: onStart)

                ArchTextButton(title: "Not now", action: onLater)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("plannerIntro.later")
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.m)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .archSheetBackground()
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

#Preview("Intro sheet") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            PlannerIntroSheet(onStart: {}, onLater: {})
        }
        .preferredColorScheme(.dark)
}

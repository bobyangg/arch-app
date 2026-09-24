import SwiftUI

/// The questionnaire, answered again.
///
/// The intro to the questions promised, from the first build, that "you can
/// change what you said later in Settings" — and there was nowhere in Settings
/// to do it. Every other thing onboarding asked for is editable on the You tab;
/// the sixteen answers were the one thing you could say once and never revisit.
/// This is that screen.
///
/// **It is the same questionnaire, not a form of sixteen.** The onboarding step
/// is reused whole — one question per screen, your previous answer already
/// picked, auto-advance on choosing — driven by an `OnboardingStore` made for
/// the purpose and thrown away after. A list of sixteen questions with sixteen
/// menus would be the form onboarding was written to avoid.
///
/// **There is a wait, and Premium waives it.** See `SettingsStore.answerAgainWait`
/// for why a month and not a day. The screen says when the wait ends rather than
/// hiding the button, because a control that vanishes reads as a bug.
struct AnswersSetting: View {
    let store: SettingsStore
    var onOpenPremium: () -> Void = {}

    /// The questionnaire in progress, or nil between runs.
    @State private var run: OnboardingStore?

    var body: some View {
        SettingsPage(title: "Your answers") {
            if let run {
                questions(run)
            } else {
                intro
            }
        }
    }

    // MARK: Before

    @ViewBuilder
    private var intro: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("\(Questionnaire.count) questions decide who reaches \(store.rosterName).")
                .archText(.body)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)
            if let when = store.answersAnsweredAt {
                Text("You last answered on \(when.formatted(.dateTime.day().month().year())).")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
        }

        if let opens = store.answerAgainAvailableOn {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("You can answer again from \(opens.formatted(.dateTime.day().month())).")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                SettingNote("Arch waits a month between one set of answers and the next, so that the people it chooses for you were chosen against something that held. Arch Premium lets you answer whenever you like.")
                ArchTextButton(title: "See Arch Premium", action: onOpenPremium)
            }
        } else {
            ArchButton(title: "Answer again") { start() }
        }

        SettingNote("Your answers are not on your profile, nobody else sees them, and they do not add up to a score. Answering again replaces what you said, and \(store.rosterName) from tomorrow is chosen against the new answers.")
    }

    /// A store with nothing in it but the questions, started on the first one
    /// with your last answers already picked.
    private func start() {
        let fresh = OnboardingStore()
        for question in Questionnaire.questions {
            if let index = store.answers[question.id], question.options.indices.contains(index) {
                fresh.questionnaireAnswers[question.id] = question.options[index]
            }
        }
        fresh.startQuestions()
        withAnimation(ArchMotion.standard) { run = fresh }
    }

    // MARK: During

    @ViewBuilder
    private func questions(_ run: OnboardingStore) -> some View {
        StepRule(total: Questionnaire.count, current: (run.questionIndex ?? 0) + 1)

        OnboardingQuestionnaire(store: run, backLeavesQuestions: false)
            .onChange(of: run.questionIndex) { _, index in
                // The onboarding store leaves the questionnaire by moving to
                // the next step; here there is no next step, so that is the
                // end, and the answers are kept.
                guard index == nil else { return }
                finish(run)
            }

        HStack(spacing: ArchSpacing.l) {
            // "Back a question" used to be here. It lives inside the
            // questionnaire now, so onboarding gets it too rather than only this
            // screen -- and so there is one of it rather than two.
            ArchTextButton(title: "Stop") {
                // Nothing is written until the last question, so stopping
                // keeps what you said before, untouched.
                withAnimation(ArchMotion.standard) { self.run = nil }
            }
        }
    }

    private func finish(_ run: OnboardingStore) {
        var chosen: [String: Int] = [:]
        for question in Questionnaire.questions {
            guard let picked = run.questionnaireAnswers[question.id],
                  let index = question.options.firstIndex(of: picked) else { continue }
            chosen[question.id] = index
        }
        store.saveAnswers(chosen)
        withAnimation(ArchMotion.standard) { self.run = nil }
    }
}

#Preview("Your answers, open") {
    NavigationStack { AnswersSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Your answers, waiting") {
    NavigationStack {
        AnswersSetting(store: {
            let store = SettingsStore()
            store.answersAnsweredAt = .now.addingTimeInterval(-3 * 24 * 60 * 60)
            return store
        }())
    }
    .preferredColorScheme(.dark)
}

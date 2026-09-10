import SwiftUI

/// Progress through a sequence of steps, as a rule broken into segments.
///
/// **Deliberately not the arch.** Filling stones as you complete onboarding is the
/// obvious idea, and building your profile really is building an arch — but the
/// arch already means "your roster slots" on the Daily 5 and in the tab bar. A shape
/// that means slot-state in one place and step-progress in another ends up meaning
/// neither, so the motif stays where it earns its keep and progress gets a plain
/// rule.
///
/// Used twice: once across onboarding, and again inside the questionnaire for its
/// own questions.
struct StepRule: View {
    let total: Int
    /// 1-based. Segments before this are done; this one is in progress.
    let current: Int

    var body: some View {
        HStack(spacing: ArchSpacing.xxs) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < current ? ArchColor.lamp : ArchColor.mortar.opacity(0.25))
                    .frame(height: 2)
            }
        }
        .animation(ArchMotion.standard, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total)")
    }
}

#Preview("Step rule") {
    VStack(spacing: ArchSpacing.xxl) {
        ForEach(1...8, id: \.self) { step in
            StepRule(total: 8, current: step)
        }
        StepRule(total: 4, current: 2)
            .padding(.top, ArchSpacing.xxl)
    }
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

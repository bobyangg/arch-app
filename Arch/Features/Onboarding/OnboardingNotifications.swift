import SwiftUI

/// The last step.
///
/// Asked here rather than at the start, because a permission prompt shown before
/// the app has done anything for you is the one everybody denies. By now there is
/// something concrete to be notified about.
///
/// The copy names exactly what gets sent. "Stay in the loop" is how you end up
/// denied and deserving it.
struct OnboardingNotifications: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Notifications",
                detail: "Two kinds, and nothing else."
            )

            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                line("One in the morning, when your five are ready.")
                line("One when somebody writes to you.")
            }

            Text("No reminders to come back, no notifications about people who have not written to you, and nothing at all in the evening.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .archText(.body)
            .foregroundStyle(ArchColor.limestone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Notifications") {
    OnboardingNotifications()
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

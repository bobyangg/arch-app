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
                detail: "One kind, and nothing else."
            )

            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                line("When somebody writes to you. That is the whole list.")
            }

            Text("Your five are waiting whenever you open Arch, and it will not tell you they are there — that is a reason to open an app, not a reason to interrupt your day. No reminders to come back, and nothing at all in the evening.")
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

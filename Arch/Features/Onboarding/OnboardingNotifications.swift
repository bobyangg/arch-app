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
        StepHeading(
            title: "Notifications",
            detail: "Notifications tell you when a potential match messages you!"
        )
    }
}

#Preview("Notifications") {
    OnboardingNotifications()
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

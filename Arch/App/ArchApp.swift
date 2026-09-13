import SwiftUI

@main
struct ArchApp: App {
    @State private var hasLaunched = false
    /// Nil until onboarding hands one over. There is no way into the app without
    /// finishing it, which is what keeps a live profile from being half-empty.
    @State private var profile: ProfileStore?
    /// Carried out of onboarding so Settings knows on the first launch, not the
    /// second, whether it is allowed to send anything.
    @State private var allowsNotifications = true
    /// Set when the account is no longer usable. It takes the whole window, because
    /// there is nothing left underneath it to navigate.
    @State private var removal: Removal?

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let removal {
                    RemovedAccountView(
                        removal: removal,
                        onAppeal: { _ in
                            withAnimation(ArchMotion.standard) { self.removal?.appeal = .sent }
                        },
                        // Not part of the design. A prototype needs a way out of a
                        // screen that is deliberately a dead end.
                        onLeave: { withAnimation(ArchMotion.standard) { self.removal = nil } }
                    )
                    .transition(.opacity)
                } else if let profile {
                    RootTabView(
                        profile: profile,
                        allowsNotifications: allowsNotifications,
                        // A deleted account is an account that has to be made
                        // again, so it lands exactly where a new one does.
                        onDeleteAccount: {
                            withAnimation(ArchMotion.standard) { self.profile = nil }
                        },
                        // The same screen, and not the same thing: deleting throws
                        // the account away, signing out leaves it where it is. A
                        // design build has nowhere to keep the difference, so it
                        // lives on the server in a real one.
                        onSignOut: {
                            withAnimation(ArchMotion.standard) { self.profile = nil }
                        }
                    )
                } else {
                    OnboardingFlowView { finished, allowed in
                        allowsNotifications = allowed
                        withAnimation(ArchMotion.standard) { profile = finished }
                    }
                }

                if !hasLaunched {
                    LaunchView { hasLaunched = true }
                        .transition(.opacity)
                }
            }
            // Arch is a dark app. There is no light variant and nothing here is
            // designed to survive one.
            .preferredColorScheme(.dark)
        }
    }
}

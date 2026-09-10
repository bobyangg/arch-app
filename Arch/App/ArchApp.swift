import SwiftUI

@main
struct ArchApp: App {
    @State private var hasLaunched = false
    /// Nil until onboarding hands one over. There is no way into the app without
    /// finishing it, which is what keeps a live profile from being half-empty.
    @State private var profile: ProfileStore?

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let profile {
                    RootTabView(profile: profile)
                } else {
                    OnboardingFlowView { finished in
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

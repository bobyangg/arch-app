import SwiftUI

@main
struct ArchApp: App {
    /// The reader's appearance choice, read straight from defaults rather than
    /// handed down through the view tree — onboarding, the tabs and the removal
    /// screen are three different roots, and all three have to honour it.
    @AppStorage(ArchTheme.storageKey) private var theme: ArchTheme = .system
    @State private var hasLaunched = false

    /// Which of the six things the app is doing, and the stores behind it.
    ///
    /// This used to be two optionals and a guess: `profile == nil` meant either
    /// "not signed in" or "signed in with nothing yet", and there was no way to
    /// say "signed in, but the train is in a tunnel". Six named states, and the
    /// screens stop inferring.
    @State private var session = ArchSession()

    var body: some Scene {
        WindowGroup {
            ZStack {
                root
                    .transition(.opacity)

                if !hasLaunched {
                    LaunchView { hasLaunched = true }
                        .transition(.opacity)
                }
            }
            // Arch has two appearances and one palette. `system` passes nil, which
            // hands the decision back to iOS — the case almost everybody is in.
            .preferredColorScheme(theme.colorScheme)
            .task {
                // Runs alongside the launch screen rather than after it, so the
                // wordmark is covering real work instead of a timer.
                await session.start()
            }
        }
    }

    @ViewBuilder
    private var root: some View {
        switch session.state {
        case .starting:
            // The launch screen is over this. Nothing to draw underneath it yet,
            // and drawing a spinner would be two loading states at once.
            Color.clear

        case .removed(let removal):
            RemovedAccountView(
                removal: removal,
                onAppeal: { body in Task { await session.appeal(body) } }
            )

        case .ready, .designBuild:
            RootTabView(
                profile: session.profile,
                injectedDaily: session.daily,
                injectedSettings: session.settings,
                allowsNotifications: session.allowsNotifications,
                onDeleteAccount: { Task { await session.deleteAccount() } },
                // The same screen, and not the same thing: deleting throws the
                // account away, signing out leaves it exactly where it is.
                onSignOut: { Task { await session.signOut() } }
            )

        case .signedOut, .onboarding:
            OnboardingFlowView { _, allowed in
                Task { await session.finishedOnboarding(allowing: allowed) }
            }

        case .unreachable:
            // Not signed out. Losing a session because a train went into a tunnel
            // would take somebody's account away for a reason that has nothing to
            // do with them.
            UnreachableView { Task { await session.refresh() } }
        }
    }
}

/// The app could not reach the server at launch.
///
/// Its own screen rather than the offline banner, because the banner sits above
/// the tabs and there are no tabs yet — there is nothing loaded to put underneath
/// it. Same register as the banner though: no red, and the second line is the
/// useful half.
struct UnreachableView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Arch cannot reach the network")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Text("Your roster and your conversations are all still there. This is a connection, and nothing here needs fixing.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            ArchButton(title: "Try again", kind: .quiet, action: onRetry)
                .padding(.top, ArchSpacing.m)
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(ArchColor.night)
    }
}

#Preview("Cannot reach the network") {
    UnreachableView(onRetry: {})
        .preferredColorScheme(.dark)
}

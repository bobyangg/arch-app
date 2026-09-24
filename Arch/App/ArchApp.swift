import SwiftUI

@main
struct ArchApp: App {
    /// The reader's appearance choice, read straight from defaults rather than
    /// handed down through the view tree — onboarding, the tabs and the removal
    /// screen are three different roots, and all three have to honour it.
    @AppStorage(ArchTheme.storageKey) private var theme: ArchTheme = .system
    /// Only for `didRegisterForRemoteNotificationsWithDeviceToken`, which is still
    /// a UIKit callback with no SwiftUI equivalent. No app state lives in it.
    @UIApplicationDelegateAdaptor(ArchAppDelegate.self) private var appDelegate
    @State private var hasLaunched = false
    /// The bridge going up again between signing in and the roster. The first
    /// roster is loading behind it, and a spinner would say "wait" where this
    /// says "here it comes".
    @State private var isBuilding = false
    /// Foreground and background. The only reason the app has for reloading
    /// without being asked — see `ArchSession.reload()`.
    @Environment(\.scenePhase) private var scenePhase

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
                } else if isBuilding {
                    LaunchView { isBuilding = false }
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

                // Registering is separate from asking. Onboarding already asked,
                // and iOS answers from its own record after the first time -- so
                // this re-registers on every launch, which is what keeps a token
                // that iOS has rotated from going stale on the server.
                if case .ready = session.state, session.allowsNotifications {
                    await PushNotifications.shared.enable()
                }
                // `scenePhase` is already `.active` at launch, so it will not
                // change and the handler below will not run. Starting here is
                // what covers the first time the app is opened.
                session.beginLiveUpdates()
            }
            // Somebody who wrote to you while the app was in your pocket is on
            // screen when you come back to it, rather than after the next cold
            // launch. `reload()` cannot fail loudly, so this is safe to do every
            // time without a network check in front of it.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    session.endLiveUpdates()
                    return
                }
                session.beginLiveUpdates()
                Task { await session.reload() }
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
                // The sequence starts before the reload, so it covers the load
                // rather than following it. Its own random pick, like a launch.
                withAnimation(ArchMotion.standard) { isBuilding = true }
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

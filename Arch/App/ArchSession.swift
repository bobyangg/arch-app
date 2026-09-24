import Observation
import SwiftUI

/// What the app is showing, and why.
///
/// One type owns the launch decision, because there are four possible answers and
/// three of them used to be represented by `nil` in different places: no session,
/// a session with no profile, a session with a profile, and an account that is no
/// longer usable. `ArchApp` read two optionals and inferred the rest.
///
/// **`.designBuild` is a first-class state, not a fallback.** Arch existed as a
/// design build long before it had a server and still has to run that way — no
/// `Info.plist` keys, no network, every screen driven by `MockData`. That is the
/// state anybody opening this project gets today, and the state every `#Preview`
/// is in.
@Observable
final class ArchSession {

    enum State {
        /// Deciding. The launch screen is over this.
        case starting
        /// No backend configured. `MockData` drives everything, exactly as before.
        case designBuild
        /// Nobody signed in. Welcome, then Apple.
        case signedOut
        /// Signed in with Apple, but there is no profile yet.
        case onboarding
        /// Signed in with a profile.
        case ready
        /// The account exists and is not usable.
        case removed(Removal)
        /// Signed in, but the first load could not reach the server.
        ///
        /// Deliberately not `signedOut`: signing somebody out because their train
        /// went into a tunnel would lose their session for a reason that has
        /// nothing to do with them.
        case unreachable
    }

    private(set) var state: State = .starting

    /// The stores, made once and handed to the tabs.
    ///
    /// Held here rather than made in `ArchApp` so that a reload after a dropped
    /// connection refreshes what the views are already showing instead of
    /// replacing the objects underneath them.
    private(set) var profile = ProfileStore()
    private(set) var daily = DailyFiveStore()
    private(set) var settings = SettingsStore()

    var allowsNotifications = true

    // MARK: Launch

    /// Works out what to show. Safe to call again after a failure.
    func start() async {
        guard ArchConfig.isConfigured else {
            // No keys: the design build, driven by the mock data the stores already
            // default to. Nothing below this line would have anywhere to go.
            state = .designBuild
            return
        }

        guard await SupabaseClient.shared.isSignedIn else {
            state = .signedOut
            return
        }

        await refresh()
    }

    /// Loads everything the app needs to open.
    func refresh() async {
        do {
            guard let account = try await ArchBackend.account() else {
                // No row, which is different from no session: the account really
                // is gone, so the credential pointing at it is worth nothing.
                // A missing *session* throws `notSignedIn` and is caught below
                // without destroying anything.
                await ArchBackend.signOut()
                state = .signedOut
                return
            }

            if account.status == "removed" {
                state = .removed(try await removal())
                return
            }

            guard let person = try await ArchBackend.ownProfile() else {
                state = .onboarding
                return
            }

            profile.adopt(person)
            try await daily.load()
            try await settings.load()
            state = .ready

        } catch ArchAPIError.notSignedIn {
            state = .signedOut
        } catch {
            // Offline, or the server is having a moment. The session is kept.
            state = .unreachable
        }
    }

    /// Reload what is already on screen, without being able to take it away.
    ///
    /// The app used to load once per process and never again: `refresh()` runs
    /// from `start()`, and nothing else called it except the retry button. So a
    /// message somebody sent you arrived in the database immediately and on your
    /// phone only after the app had been force-quit and opened cold — putting it
    /// in the background and coming back showed yesterday's roster and an empty
    /// messages list. Sending worked; receiving waited for a relaunch.
    ///
    /// Separate from `refresh()` because coming back to the app is not launching
    /// it. `refresh()` is allowed to decide you are signed out, removed, or
    /// unreachable, and that is right at launch. Here it would mean that walking
    /// into a lift with Arch open replaces the screen you were reading with an
    /// error — so a failure leaves everything exactly as it was, and the next
    /// return tries again.
    func reload() async {
        guard case .ready = state else { return }
        // No `account()` and no `ownProfile()`: this is a refresh of the two
        // stores the tabs are reading, not a re-decision about who you are.
        try? await daily.load()
        try? await settings.load()
    }

    /// Start and stop the polling that keeps messages arriving.
    ///
    /// Tied to the app being in front rather than to any screen: a message can
    /// arrive while you are on the roster or in Settings, and the unread count
    /// on the tab is the whole point of knowing about it there. Stopped on the
    /// way out, because a timer running in a backgrounded app is a request every
    /// twelve seconds that nobody is waiting for.
    func beginLiveUpdates() {
        guard case .ready = state else { return }
        daily.beginLiveUpdates()
    }

    func endLiveUpdates() {
        daily.endLiveUpdates()
    }

    /// What the removal screen needs. Falls back to the least specific version
    /// rather than failing: a reader who cannot get in deserves an explanation even
    /// when the detail did not load.
    private func removal() async throws -> Removal {
        guard let row = try? await ArchBackend.removal() else {
            return Removal(kind: .removed, reason: .other)
        }
        // `paused` carries the date it lifts, so the kind cannot be built from the
        // string alone — a paused account with no date would be a screen saying
        // "until" and then nothing.
        let kind: Removal.Kind
        switch row.kind {
        case "paused":
            kind = .paused(until: ArchUnits.relative(row.until))
        case "device":
            kind = .device
        default:
            kind = .removed
        }
        return Removal(
            kind: kind,
            reason: RemovalReason(rawValue: row.reason) ?? .other
        )
    }

    // MARK: Moving between states

    /// Apple has said who somebody is and the server has taken it.
    func signedIn(needsOnboarding: Bool) async {
        if needsOnboarding {
            state = .onboarding
        } else {
            await refresh()
        }
    }

    /// Onboarding finished. Everything it wrote is already on the server, so this
    /// reloads rather than trusting what the flow had in memory.
    func finishedOnboarding(allowing notifications: Bool) async {
        allowsNotifications = notifications
        await refresh()
    }

    /// Local only. The account, the conversations and the roster stay exactly as
    /// they are, and signing back in with Apple lands straight back on them.
    func signOut() async {
        await ArchBackend.signOut()
        profile = ProfileStore()
        daily = DailyFiveStore()
        settings = SettingsStore()
        state = .signedOut
    }

    /// Immediate and permanent, as the screen says. Lands where a new account does.
    func deleteAccount() async {
        try? await ArchBackend.deleteAccount()
        await signOut()
    }

    /// An appeal, recorded so the screen can say it was received.
    func appeal(_ body: String) async {
        guard case .removed(var removal) = state else { return }
        if let row = try? await ArchBackend.removal() {
            try? await ArchBackend.appeal(removalID: row.id, body: body)
        }
        removal.appeal = .sent
        state = .removed(removal)
    }
}

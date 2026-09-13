import SwiftUI
import UIKit
import UserNotifications

/// Asking iOS for permission, and telling the server where to send.
///
/// **One notification exists**: somebody wrote to you. Onboarding names it in as
/// many words before this ever runs, which is the whole reason to prime a
/// permission prompt rather than fire it at launch — "stay in the loop" is how you
/// end up denied and deserving it.
///
/// Nothing here is a badge, a reminder, or anything about the roster. Your five are
/// there when you open the app, and telling you they have arrived would be a reason
/// to open an app rather than a reason to interrupt a day.
@MainActor
final class PushNotifications: NSObject, ObservableObject {

    static let shared = PushNotifications()

    /// Ask, then register. Safe to call again — iOS answers from its own record
    /// after the first time and shows no second prompt.
    func enable() async {
        guard ArchConfig.isConfigured else { return }
        let centre = UNUserNotificationCenter.current()
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound]))
            ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Whether iOS is currently willing to deliver anything.
    ///
    /// Read rather than remembered: somebody can turn Arch's notifications off in
    /// their phone's settings at any time, and Settings has to say so instead of
    /// showing a switch that cannot do anything.
    func isAllowedBySystem() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// APNs handed over a token for this install.
    func received(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await ArchBackend.savePushToken(hex, environment: Self.environment) }
    }

    /// Which of Apple's two hosts this build's tokens belong to.
    ///
    /// A sandbox token sent to the production host fails with `BadDeviceToken`,
    /// which looks exactly like "notifications are broken" — for a week, because
    /// nobody thinks to check which APNs host they are talking to.
    ///
    /// `DEBUG` is the right line here and not merely the easy one: Xcode's
    /// development profiles carry `aps-environment: development`, and TestFlight
    /// and App Store builds are release builds carrying `production`. Reading the
    /// embedded provisioning profile would be more precise and is worth doing only
    /// if a build ever manages to be one and claim the other.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

/// The one thing SwiftUI has no hook for.
///
/// Remote-notification registration is still a `UIApplicationDelegate` callback,
/// so there has to be a delegate — but it does exactly this and nothing else, and
/// no app state lives here.
final class ArchAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotifications.shared.received(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Not shown to anybody. A phone with no push certificate, no network at
        // launch, or a simulator all land here, and none of them is something the
        // reader did or can fix. The app works; it is quieter.
        print("Push registration failed: \(error.localizedDescription)")
    }
}

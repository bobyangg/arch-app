import SwiftUI
import UIKit

/// Your email.
///
/// **Shown, not edited, and it used to be neither.** This was a text field over a
/// hard-coded `sam@example.com` that saved into a variable nothing read and
/// nothing persisted — an address that was not yours, presented as though it were.
///
/// Arch does not ask for an email and does not need to: signing in with Apple
/// already supplies one, Apple has verified it, and asking again would be asking
/// for something we hold. It cannot be changed from here either, because it is not
/// Arch's to change — it belongs to the Apple ID, and iOS is where it is changed.
struct EmailSetting: View {
    let store: SettingsStore

    /// Apple's forwarding address, for somebody who chose Hide My Email. Worth
    /// naming on screen, because an unexplained `2r8vhk9p8c@privaterelay.appleid.com`
    /// reads as a mistake.
    private var isRelay: Bool {
        store.email?.hasSuffix("privaterelay.appleid.com") ?? false
    }

    var body: some View {
        SettingsPage(title: "Email") {
            Text(store.email ?? "Not loaded")
                .archText(.titleM)
                .foregroundStyle(store.email == nil ? ArchColor.mortar : ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            if isRelay {
                SettingNote("Apple\u{2019}s Hide My Email address. Mail sent here reaches your inbox.")
            }

        }
    }
}

/// Your subscription.
///
/// Sends you to the Premium tab rather than rebuilding the paywall here — the same
/// screen in two places is two screens to keep honest.
struct PremiumSetting: View {
    let store: SettingsStore
    var onOpen: () -> Void = {}

    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPage(title: "Arch Premium") {
            Text(store.premiumText)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)

            if store.isSubscribed {
                SettingNote("Cancel any time in your Apple account. Premium runs to the end of what you paid for.")
                // Apple's own subscriptions page, where cancelling happens.
                ArchButton(title: "Manage in Apple settings", kind: .quiet) {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
                }
            } else {
                SettingNote("More matches and more open conversations. It doesn\u{2019}t change who sees you.")
                ArchButton(title: "See what premium changes", action: onOpen)
                ArchTextButton(title: "Restore purchases") {
                    Task { await Purchases.shared.restore() }
                }
            }
        }
    }
}

/// Deleting your account.
///
/// **Three consequences, named.** "This cannot be undone" on its own says nothing
/// — every confirmation in every app says it. The one that matters here is the one
/// nobody expects: the people you are mid-conversation with watch it disappear
/// from their phone.
///
/// **Short, and the button is red.** Three lines say what happens; the button
/// is the one red thing in Arch (`ArchColor.danger`), because this is the one
/// thing that cannot be taken back. The row in Settings stays the same stone as
/// every other row.
///
/// Pause is mentioned once, in a line, because a good share of people reaching
/// for this want a break rather than an ending -- never standing between you
/// and the thing you came here to do.
struct DeleteAccountSetting: View {
    let store: SettingsStore
    var onDelete: () -> Void = {}

    @State private var isConfirming = false

    var body: some View {
        SettingsPage(title: "Delete your account") {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                point("person.crop.circle.badge.xmark", "Your profile, photos and answers are deleted.")
                point("bubble.left", "People you\u{2019}re talking to keep what was said, but can\u{2019}t reply.")
                // Deleting does not burn the Apple ID (`backend/016`): signing
                // in again starts a new profile from scratch.
                point("arrow.uturn.backward", "This can\u{2019}t be undone.")
            }

            SettingNote("Need a break instead? Pause your profile in Discovery.")

            ArchButton(title: "Delete my account", kind: .destructive) { isConfirming = true }
                .accessibilityIdentifier("settings.delete")
        }
        .sheet(isPresented: $isConfirming) {
            DeleteConfirmSheet(
                onConfirm: {
                    isConfirming = false
                    onDelete()
                },
                onCancel: { isConfirming = false }
            )
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ArchSpacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(ArchColor.mortar)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .archText(.body)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The last step, built like `LeaveConfirmSheet` — a sheet rather than an alert,
/// because an alert is something you swat away and this is not.
struct DeleteConfirmSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Delete your account?")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xl)

            Text("Your profile goes now, and your conversations stop. This can\u{2019}t be undone.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            Spacer(minLength: ArchSpacing.xl)

            ArchButton(title: "Delete my account", kind: .destructive, action: onConfirm)
                .accessibilityIdentifier("settings.deleteConfirm")
            ArchTextButton(title: "Cancel", action: onCancel)
                .padding(.top, ArchSpacing.xxs)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchColor.stone)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .archSheetBackground()
    }
}

/// iOS has said no, so there is nothing for the three switches to switch.
///
/// Stating it once and pointing at the place that can fix it is the whole screen.
/// Leaving the switches on display would be the app pretending to a power it does
/// not have.
struct NotificationsBlockedSetting: View {
    let store: SettingsStore

    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPage(title: "Notifications are off") {
            Text("Arch cannot send you anything")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            SettingNote("Turn them on for Arch in iPhone Settings. Arch only notifies you when someone writes.")

            ArchButton(title: "Open iPhone settings", kind: .quiet) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }
}


/// Signing out.
///
/// Worth a sheet rather than a bare row, because with no password the cost is not
/// obvious: getting back in means a code, and somebody who has changed phones may
/// not be able to. Nothing is lost either way, and the sheet says so first — the
/// fear this raises is that signing out is deleting, and it is not.
struct SignOutConfirmSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sign out?")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xl)

            Text("Nothing is deleted. Sign back in any time to pick up where you left off.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            Spacer(minLength: ArchSpacing.xl)

            ArchButton(title: "Sign out", kind: .quiet, action: onConfirm)
            ArchTextButton(title: "Cancel", action: onCancel)
                .padding(.top, ArchSpacing.xxs)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchColor.stone)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .archSheetBackground()
    }
}

#Preview("Signing out") {
    SignOutConfirmSheet(onConfirm: {}, onCancel: {})
        .frame(height: 260)
        .preferredColorScheme(.dark)
}

#Preview("Delete your account") {
    NavigationStack { DeleteAccountSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Deleting, confirming") {
    DeleteConfirmSheet(onConfirm: {}, onCancel: {})
        .frame(height: 260)
        .preferredColorScheme(.dark)
}

#Preview("Notifications denied") {
    NavigationStack { NotificationsBlockedSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Email") {
    NavigationStack {
        EmailSetting(store: {
            let s = SettingsStore()
            s.email = "2r8vhk9p8c@privaterelay.appleid.com"
            return s
        }())
    }
    .preferredColorScheme(.dark)
}

/// Somebody who shared their real address rather than hiding it, so the relay
/// explanation is absent.
#Preview("Email, not hidden") {
    NavigationStack {
        EmailSetting(store: {
            let s = SettingsStore()
            s.email = "sam@fastmail.com"
            return s
        }())
    }
    .preferredColorScheme(.dark)
}

#Preview("Premium, not subscribed") {
    NavigationStack { PremiumSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}


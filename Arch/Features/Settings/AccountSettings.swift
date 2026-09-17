import SwiftUI

/// Your email.
struct EmailSetting: View {
    let store: SettingsStore
    @State private var draft = ""

    var body: some View {
        SettingsPage(title: "Email") {
            ArchField(
                text: $draft,
                placeholder: "sam@example.com",
                keyboard: .emailAddress,
                surface: ArchColor.stone
            )

            SettingNote("Used for signing in and account notices. Never shown to anyone, and Arch does not send anything else here.")

            ArchButton(title: "Save", isEnabled: isValid && draft != store.email) {
                store.email = draft.trimmed
            }
        }
        .onAppear { draft = store.email }
    }

    private var isValid: Bool {
        let t = draft.trimmed
        return t.contains("@") && !t.hasPrefix("@") && !t.hasSuffix("@")
    }
}

/// Your subscription.
///
/// Sends you to the Premium tab rather than rebuilding the paywall here — the same
/// screen in two places is two screens to keep honest.
struct PremiumSetting: View {
    let store: SettingsStore
    var onOpen: () -> Void = {}

    var body: some View {
        SettingsPage(title: "Arch Premium") {
            Text(store.premiumText)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)

            if store.isSubscribed {
                SettingNote("Renews on the 14th. You can cancel any time in your Apple account settings, and premium runs until the end of the period you have paid for.")
                ArchButton(title: "Manage in Apple settings", kind: .quiet) {}
            } else {
                SettingNote("Premium changes how many people you can hold and how many conversations you can keep open. It does not change who sees you.")
                ArchButton(title: "See what premium changes", action: onOpen)
                ArchTextButton(title: "Restore purchases") {}
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
/// **No red and no lurid styling.** Arch has no red anywhere, and dressing this up
/// as a hazard would be a way of discouraging something you are entitled to do.
/// The row in Settings is the same stone as every other row.
///
/// Pause is mentioned once, quietly, because a good share of people reaching for
/// this want a break rather than an ending. Once — not as a competing button, and
/// never standing between you and the thing you came here to do.
struct DeleteAccountSetting: View {
    let store: SettingsStore
    var onDelete: () -> Void = {}

    @State private var isConfirming = false

    var body: some View {
        SettingsPage(title: "Delete your account") {
            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                line("Your profile, photos and answers are deleted.")
                line("The people you are talking to can still read what was said, and cannot reply. They are not told why.")
                // Was "the same number can start again from scratch", which was
                // wrong twice over: phone verification went when Apple sign-in
                // arrived, and `delete_account` deliberately keeps the Apple id
                // claimed so that somebody removed for abuse cannot delete their
                // way to a clean one.
                line("You cannot undo this, and this Apple ID cannot make another account.")
            }

            SettingNote("If you want to stop for a while rather than leave, pause your profile instead. Paused, nobody new arrives and you are not in anyone else's roster, but your conversations keep working.")

            ArchButton(title: "Delete my account", kind: .quiet) { isConfirming = true }
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

    private func line(_ text: String) -> some View {
        Text(text)
            .archText(.body)
            .foregroundStyle(ArchColor.limestone)
            .fixedSize(horizontal: false, vertical: true)
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

            Text("Your profile goes now, and every conversation you are in stops. There is no undo and no grace period.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            Spacer(minLength: ArchSpacing.xl)

            ArchButton(title: "Delete my account", kind: .quiet, action: onConfirm)
            ArchTextButton(title: "Cancel", action: onCancel)
                .padding(.top, ArchSpacing.xxs)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchColor.stone)
        .presentationDetents([.height(300)])
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

    var body: some View {
        SettingsPage(title: "Notifications are off") {
            Text("Arch cannot send you anything")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            SettingNote("Notifications are turned off for Arch in your iPhone settings. Nothing here can change that — turn them back on there and your choices come back exactly as you left them.")

            ArchButton(title: "Open iPhone settings", kind: .quiet) {}

            SettingNote("Arch only ever sends one, and only when a person writes to you. It has never had a reason to tell you to come back.")
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

            Text("Your profile, your conversations and the people in your roster all stay exactly as they are. Nothing is deleted. Signing back in with Apple brings you straight back to it.")
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
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .archSheetBackground()
    }
}

#Preview("Signing out") {
    SignOutConfirmSheet(onConfirm: {}, onCancel: {})
        .frame(height: 320)
        .preferredColorScheme(.dark)
}

#Preview("Delete your account") {
    NavigationStack { DeleteAccountSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Deleting, confirming") {
    DeleteConfirmSheet(onConfirm: {}, onCancel: {})
        .frame(height: 300)
        .preferredColorScheme(.dark)
}

#Preview("Notifications denied") {
    NavigationStack { NotificationsBlockedSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Email") {
    NavigationStack { EmailSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Premium, not subscribed") {
    NavigationStack { PremiumSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}


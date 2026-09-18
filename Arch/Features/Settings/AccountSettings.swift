import SwiftUI

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
                SettingNote("You chose Hide My Email when you signed in, so this is "
                            + "Apple's forwarding address. Anything sent here reaches "
                            + "your real inbox, and Arch never sees the address behind it.")
            }

            SettingNote("This comes from your Apple ID. Arch never shows it to "
                        + "anyone and sends nothing to it today — if that changes it "
                        + "will be account notices and nothing else.")

            SettingNote("To change it, open iOS Settings, tap your name, then Sign "
                        + "in with Apple, then Arch. It is not Arch's to change.")
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
                // **Said the opposite of what happens, and made it true.**
                // `delete_account` set `status = 'removed'`, which `register`
                // refuses, so this sentence was accurate and the behaviour it
                // described was a bug -- deleting burned the Apple ID with no
                // route back. `backend/016` separated the moderation state from
                // the fact of having deleted; somebody who leaves can sign in
                // again and start over, and only moderation refuses anybody.
                line("You cannot undo this. Nothing here comes back, and starting again means building a profile from scratch.")
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


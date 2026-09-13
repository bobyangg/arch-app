import SwiftUI

/// Your number.
///
/// Read-only, with changing it behind a deliberate action — the number is the
/// verification, so changing it means verifying again, and the screen says so
/// before you start rather than after.
struct PhoneSetting: View {
    let store: SettingsStore

    @State private var isChanging = false

    var body: some View {
        SettingsPage(title: "Phone number") {
            Text(store.phone)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)

            SettingNote("This is how Arch knows you are a person. It is never shown to anyone and never appears on your profile.")

            ArchButton(title: "Change number", kind: .quiet) { isChanging = true }

            SettingNote("You will have to verify the new number before it takes effect.")
        }
        .sheet(isPresented: $isChanging) {
            ChangeNumberSheet(current: store.phone) { store.phone = $0 }
        }
    }
}

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
                line("You cannot undo this, and the same number can start again from scratch.")
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
        .presentationBackground(ArchColor.stone)
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

/// Changing the number.
///
/// The number *is* the sign-in — there is no password to fall back on — so
/// changing it is the verification flow again rather than a field you edit. Two
/// screens in one sheet, the same shape onboarding uses.
///
/// **The number already being taken is a real ending, not an error.** Two accounts
/// cannot share one, and the way out is to sign out and sign in with it, so the
/// screen says that instead of blinking red and leaving you to work it out.
struct ChangeNumberSheet: View {
    let current: String
    let onChange: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var code = ""
    @State private var step: Step = .number
    @FocusState private var focused: Bool

    enum Step { case number, code, taken, done }

    /// A design build has no carrier, so one number stands in for one that is
    /// already in use. A real build asks the server.
    private var isTaken: Bool { digits.hasSuffix("0000") }
    private var digits: String { number.filter(\.isNumber) }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            switch step {
            case .number: numberStep
            case .code:   codeStep
            case .taken:  takenStep
            case .done:   doneStep
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
    }

    // MARK: Steps

    private var numberStep: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            title("A new number")
            detail("Arch verifies every number, so you will get a code before anything changes. Until then \(current) still signs you in.")

            HStack(spacing: ArchSpacing.xs) {
                Text("+1")
                    .archText(.callout)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(ArchSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                            .fill(ArchColor.night)
                    )
                ArchField(text: $number, placeholder: "917 555 0142", keyboard: .phonePad)
            }

            Spacer(minLength: 0)

            ArchButton(title: "Send a code", isEnabled: digits.count >= 7) {
                step = isTaken ? .taken : .code
            }
            ArchTextButton(title: "Cancel") { dismiss() }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            title("Check your messages")
            detail("We sent a six-digit code to +1 \(number).")

            ZStack {
                TextField("", text: Binding(
                    get: { code },
                    set: { code = String($0.filter(\.isNumber).prefix(6)) }
                ))
                .keyboardType(.numberPad)
                .focused($focused)
                .opacity(0.01)

                HStack(spacing: ArchSpacing.xs) {
                    ForEach(0..<6, id: \.self) { index in
                        Text(digit(at: index))
                            .archText(.titleM)
                            .foregroundStyle(ArchColor.limestone)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                                    .fill(ArchColor.night)
                            )
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            Spacer(minLength: 0)

            ArchButton(title: "Verify", isEnabled: code.count == 6) {
                onChange("+1 \(number)")
                step = .done
            }
            ArchTextButton(title: "Use a different number") {
                code = ""
                step = .number
            }
        }
        .onAppear { focused = true }
    }

    private var takenStep: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            title("That number already has an account")
            detail("Two accounts cannot share a number. If that one is yours, sign out and sign in with it instead — this account stays exactly as it is until you do.")

            Spacer(minLength: 0)

            ArchButton(title: "Try another number", kind: .quiet) {
                number = ""
                step = .number
            }
            ArchTextButton(title: "Cancel") { dismiss() }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            title("Your number has changed")
            detail("+1 \(number) signs you in from now on. The old one does not reach this account any more, and nothing else about your profile moved.")

            Spacer(minLength: 0)

            ArchButton(title: "Done") { dismiss() }
        }
    }

    // MARK: Pieces

    private func title(_ text: String) -> some View {
        Text(text)
            .archText(.titleM)
            .foregroundStyle(ArchColor.limestone)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, ArchSpacing.l)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .archText(.body)
            .foregroundStyle(ArchColor.mortar)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func digit(at index: Int) -> String {
        let characters = Array(code)
        return index < characters.count ? String(characters[index]) : ""
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
        .presentationBackground(ArchColor.stone)
    }
}

#Preview("Change number") {
    ChangeNumberSheet(current: "+1 (917) 555 0142") { _ in }
        .frame(height: 420)
        .preferredColorScheme(.dark)
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

#Preview("Phone number") {
    NavigationStack { PhoneSetting(store: SettingsStore()) }
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


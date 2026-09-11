import SwiftUI

/// Your number.
///
/// Read-only, with changing it behind a deliberate action — the number is the
/// verification, so changing it means verifying again, and the screen says so
/// before you start rather than after.
struct PhoneSetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Phone number") {
            Text(store.phone)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)

            SettingNote("This is how Arch knows you are a person. It is never shown to anyone and never appears on your profile.")

            ArchButton(title: "Change number", kind: .quiet) {}

            SettingNote("You will have to verify the new number before it takes effect.")
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

/// When the morning notification arrives.
struct TimeSetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Time") {
            VStack(spacing: ArchSpacing.xs) {
                ForEach(SettingsStore.times, id: \.self) { time in
                    OptionRow(text: time, isSelected: store.dailyFiveTime == time) {
                        store.dailyFiveTime = time
                    }
                }
            }

            SettingNote("\(store.rosterTitle) are ready at the same time every day. This only changes when Arch tells you about them.")
        }
    }
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

#Preview("Notification time") {
    NavigationStack { TimeSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

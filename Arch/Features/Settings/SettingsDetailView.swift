import SwiftUI

/// The shell every settings detail sits in: back, title, a scroll.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ArchSpacing.s) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                        .frame(
                            width: ArchSpacing.minimumTapTarget,
                            height: ArchSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Back to settings")

                Text(title)
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)

                Spacer(minLength: 0)
            }
            .padding(.leading, ArchSpacing.xs)
            .padding(.trailing, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.xs)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: ArchSpacing.xl) {
                    content
                }
                .padding(.horizontal, ArchSpacing.screenMargin)
                .padding(.top, ArchSpacing.xl)
                .padding(.bottom, ArchSpacing.sectionGap)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .background(ArchColor.night)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A line under a control explaining what it actually does. Every setting in Arch
/// gets one — a switch with no explanation is a switch people leave alone.
struct SettingNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .archText(.footnote)
            .foregroundStyle(ArchColor.mortar)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Routes a row to its screen.
struct SettingsDetailView: View {
    let row: SettingsRow
    let store: SettingsStore
    var onOpenPremium: () -> Void = {}
    var onDeleteAccount: () -> Void = {}

    var body: some View {
        switch row.id {
        case "a-phone":    PhoneSetting(store: store)
        case "a-email":    EmailSetting(store: store)
        case "a-premium":  PremiumSetting(store: store, onOpen: onOpenPremium)
        case "a-delete":   DeleteAccountSetting(store: store, onDelete: onDeleteAccount)
        case "n-blocked":  NotificationsBlockedSetting(store: store)
        case "x-theme":    AppearanceSetting(store: store)
        case "d-seeking":  SeekingSetting(store: store)
        case "d-distance": DistanceSetting(store: store)
        case "d-age":      AgeSetting(store: store)
        case "d-intent":   IntentionSetting(store: store)
        case "p-visible":  VisibilitySetting(store: store)
        case "p-blocked":  BlockedSetting(store: store)
        case "p-data":     DataSetting(store: store)
        case "h-how":      HelpPage(topic: .how)
        case "h-safety":   HelpPage(topic: .safety)
        case "h-contact":  HelpPage(topic: .contact)
        default:
            // Not dead code: a `switch` over a `String` has no exhaustive form, so
            // this is the compiler's requirement *and* what stops a mistyped row
            // id becoming a screen with nothing on it.
            SettingsPage(title: row.title) {
                SettingNote("This setting is not built yet.")
            }
        }
    }
}

#Preview("Distance") {
    NavigationStack { DistanceSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

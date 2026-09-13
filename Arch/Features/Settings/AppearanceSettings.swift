import SwiftUI

/// Light and dark.
///
/// Three rows and a specimen. The specimen is there because an appearance setting
/// that only lists words makes you commit before you can see anything — you pick,
/// leave, and find out on the next screen. Here the card above the rows is the app's
/// own surfaces, type and accent, and it changes as you choose.
struct AppearanceSetting: View {
    let store: SettingsStore

    /// `system` has no answer of its own, so the specimen shows whatever the phone
    /// is currently doing.
    @Environment(\.colorScheme) private var current
    private var previewScheme: ColorScheme { store.theme.colorScheme ?? current }

    var body: some View {
        SettingsPage(title: "Light and dark") {
            AppearanceSpecimen()
                .environment(\.colorScheme, previewScheme)
                .animation(ArchMotion.standard, value: store.theme)

            VStack(spacing: ArchSpacing.xs) {
                ForEach(ArchTheme.allCases) { option in
                    OptionRow(text: option.title, isSelected: store.theme == option) {
                        store.theme = option
                    }
                }
            }

            SettingNote(store.theme.note)

            if !ArchFonts.areBrandFacesAvailable {
                // Only ever seen in a build that is missing the font files. Saying
                // so beats letting somebody conclude the brand looks like SF.
                SettingNote("Arch's own typefaces are not in this build, so the system fonts are standing in.")
            }
        }
    }
}

/// A small piece of the app, built out of the same tokens as the real thing — the
/// wordmark, a line of each family, and the one button that carries the accent.
private struct AppearanceSpecimen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            HStack(spacing: ArchSpacing.s) {
                ArchMark(lineWidth: 3.4)
                    .stroke(
                        ArchColor.lamp,
                        style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 30, height: 30 * ArchMark.aspect)

                Text("arch")
                    .font(ArchTypography.font(.frauncesDisplaySemiBold, size: 24))
                    .foregroundStyle(ArchColor.limestone)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                Text("The last thing I read twice")
                    .archText(.prompt)
                    .foregroundStyle(ArchColor.mortar)
                Text("A field guide to bridges I found in my grandad's garage.")
                    .archText(.callout)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Send a message")
                .archText(.subhead)
                .foregroundStyle(ArchColor.onLamp)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                        .fill(ArchColor.lamp)
                )
        }
        .padding(ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .strokeBorder(ArchColor.hairline, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

#Preview("Appearance") {
    NavigationStack { AppearanceSetting(store: SettingsStore()) }
}

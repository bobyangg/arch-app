import SwiftUI

/// Light and dark.
///
/// Three rows. There used to be a specimen card above them -- a small piece of
/// the app drawn in whichever look was chosen -- but choosing changes the whole
/// screen at once, so the card only repeated what the page around it already
/// showed.
struct AppearanceSetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Light and dark") {
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

#Preview("Appearance") {
    NavigationStack { AppearanceSetting(store: SettingsStore()) }
}

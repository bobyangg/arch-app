import SwiftUI

/// Placeholder for the You tab.
///
/// The real screen — your own profile rendered as others see it, with edit
/// affordances, and a way into settings — is the next milestone. This exists so the
/// fourth tab does not dead-end while the rest of the app is navigable.
struct YouPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Spacer()
            Text("You")
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)
            Text("Your profile and settings are not built yet.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(ArchColor.night)
    }
}

#Preview("You, placeholder") {
    YouPlaceholderView()
        .preferredColorScheme(.dark)
}

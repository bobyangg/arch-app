import SwiftUI

/// Where every settings row lands.
///
/// A placeholder, but an honest one: it names the setting it belongs to and says
/// plainly that the controls are not built. A row that silently goes nowhere is
/// worse than a row that admits it.
struct SettingsDetailView: View {
    let row: SettingsRow

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                if let detail = row.detail {
                    Text(detail)
                        .archText(.titleM)
                        .foregroundStyle(ArchColor.limestone)
                }
                Text("The controls for this setting are not built yet.")
                    .archText(.body)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.top, ArchSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ArchColor.night)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: ArchSpacing.s) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: ArchSpacing.minimumTapTarget, height: ArchSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Back to settings")

            Text(row.title)
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
    }
}

#Preview("Settings detail") {
    NavigationStack {
        SettingsDetailView(row: MockData.settingsSections[2].rows[1])
    }
    .preferredColorScheme(.dark)
}

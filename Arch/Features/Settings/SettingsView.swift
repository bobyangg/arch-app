import SwiftUI

/// Settings.
///
/// A grouped list on `stone` rather than a system `List`, so the surfaces match the
/// rest of the app instead of arriving with their own greys. Every row goes
/// somewhere — nothing here dead-ends.
struct SettingsView: View {
    var sections: [SettingsSection] = MockData.settingsSections

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: ArchSpacing.xl) {
                    ForEach(sections) { section in
                        group(section)
                    }
                    signOut
                    version
                }
                .padding(.horizontal, ArchSpacing.screenMargin)
                .padding(.top, ArchSpacing.l)
                .padding(.bottom, ArchSpacing.sectionGap)
            }
            .scrollIndicators(.hidden)
        }
        .background(ArchColor.night)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: SettingsRow.self) { row in
            SettingsDetailView(row: row)
        }
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
            .accessibilityLabel("Back to your profile")

            Text("Settings")
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

    private func group(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Text(section.title)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .padding(.leading, ArchSpacing.xxs)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    NavigationLink(value: row) {
                        SettingsRowView(row: row)
                    }
                    .buttonStyle(PressScaleStyle(scale: 1))

                    if index < section.rows.count - 1 {
                        Rectangle()
                            .fill(ArchColor.hairline)
                            .frame(height: ArchSpacing.hairline)
                            .padding(.leading, ArchSpacing.m)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                    .fill(ArchColor.stone)
            )
        }
    }

    /// Quiet, not `lamp`. Signing out is not what the app is encouraging, and it is
    /// not an emergency either.
    private var signOut: some View {
        Button {} label: {
            Text("Sign out")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ArchSpacing.m)
                .padding(.vertical, ArchSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                        .fill(ArchColor.stone)
                )
        }
        .buttonStyle(PressScaleStyle(scale: 1))
    }

    private var version: some View {
        Text("Arch 1.0")
            .archText(.footnote)
            .foregroundStyle(ArchColor.mortar)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, ArchSpacing.s)
    }
}

struct SettingsRowView: View {
    let row: SettingsRow

    var body: some View {
        HStack(spacing: ArchSpacing.s) {
            Text(row.title)
                .archText(.body)
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: ArchSpacing.s)

            if let detail = row.detail {
                Text(detail)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .archText(.caption)
                .foregroundStyle(ArchColor.mortar)
        }
        .padding(.horizontal, ArchSpacing.m)
        .padding(.vertical, ArchSpacing.m)
        .contentShape(Rectangle())
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}

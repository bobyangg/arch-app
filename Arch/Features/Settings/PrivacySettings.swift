import SwiftUI

/// Whether Arch can keep putting you in other people's fives.
///
/// The second option is the one that only makes sense in a slow app: stop new
/// people arriving while you still owe someone a reply. Every other app would call
/// that losing momentum. Here it is the point.
struct VisibilitySetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Who can see me") {
            VStack(spacing: ArchSpacing.xs) {
                ForEach(SettingsStore.visibilities, id: \.self) { option in
                    OptionRow(text: option, isSelected: store.visibility == option) {
                        store.visibility = option
                    }
                }
            }

            SettingNote("Either way you keep the people already in \(store.rosterName), and they keep you. To come off Arch entirely, pause your profile.")
        }
    }
}

/// People you have blocked.
struct BlockedSetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Blocked people") {
            if store.blocked.isEmpty {
                Text("Nobody blocked")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                SettingNote("Blocking someone takes them out of \(store.rosterName), stops them appearing again, and stops you appearing in theirs. They are not told.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.blocked.enumerated()), id: \.offset) { index, name in
                        HStack {
                            Text(name)
                                .archText(.body)
                                .foregroundStyle(ArchColor.limestone)
                            Spacer(minLength: 0)
                            Button { store.blocked.removeAll { $0 == name } } label: {
                                Text("Unblock")
                                    .archText(.footnote)
                                    .foregroundStyle(ArchColor.mortar)
                            }
                            .buttonStyle(PressScaleStyle(scale: 1))
                        }
                        .padding(ArchSpacing.m)

                        if index < store.blocked.count - 1 {
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
    }
}

/// A copy of everything Arch holds.
struct DataSetting: View {
    let store: SettingsStore
    @State private var requested = false

    var body: some View {
        SettingsPage(title: "Download your data") {
            Text("Everything Arch holds about you")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                line("Your profile, including photos and answers.")
                line("Your questionnaire answers.")
                line("Every message you have sent and received.")
                line("Who has been in \(store.rosterName), and when.")
            }

            SettingNote("Sent as a file to \(store.email). It usually takes a few minutes and never more than 30 days.")

            ArchButton(title: requested ? "Requested" : "Request my data",
                       kind: .quiet,
                       isEnabled: !requested) {
                requested = true
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .archText(.body)
            .foregroundStyle(ArchColor.limestone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Who can see me") {
    NavigationStack { VisibilitySetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Blocked, empty") {
    NavigationStack { BlockedSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Blocked, with people") {
    NavigationStack {
        BlockedSetting(store: {
            let s = SettingsStore()
            s.blocked = ["Someone from work", "A person in Bushwick"]
            return s
        }())
    }
    .preferredColorScheme(.dark)
}

#Preview("Download your data") {
    NavigationStack { DataSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

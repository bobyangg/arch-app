import SwiftUI

/// People you have blocked.
struct BlockedSetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Blocked people") {
            if store.blocked.isEmpty {
                Text("Nobody blocked")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                SettingNote("Blocked people leave your matches for good. They\u{2019}re never told.")
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

/// A copy of everything Arch holds, as one file you save or send.
///
/// **What it is, said plainly.** The page used to promise a folder with your
/// photographs at full size; what is built is one JSON file from
/// `private.export_payload`, which lists your photos rather than including
/// them. The page now says what the file is.
///
/// What it deliberately leaves out is the more interesting half, and it lives in
/// `private.export_payload` where it can be tested rather than in the exporter
/// where it would be a `select` written in a hurry: no compatibility score, no
/// record of who dismissed or blocked you, no reports, and no profile of anybody
/// else beyond their name. A year of rosters with profiles attached is a dossier,
/// not your data.
struct DataSetting: View {
    let store: SettingsStore

    /// What has happened so far. Four states rather than a boolean, because
    /// "asked", "working", "here" and "did not work" all need different words and
    /// a boolean would have to pick two of them.
    private enum Stage: Equatable {
        case ready
        case working
        case made(URL)
        case failed(String)
    }

    @State private var stage: Stage = .ready

    var body: some View {
        SettingsPage(title: "Download your data") {
            Text("Everything Arch holds about you")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                line("Your profile and answers")
                line("Your messages")
                line("Who you\u{2019}ve been matched with, and when")
            }

            // **Made here and handed straight over.** It was going to be emailed,
            // which needed a mail provider that does not exist yet.
            SettingNote("One file, made on your phone. Save it to Files or send it anywhere.")

            switch stage {
            case .ready:
                ArchButton(title: "Build my file", kind: .quiet, action: build)

            case .working:
                ArchButton(title: "Building…", kind: .quiet, isEnabled: false) {}

            case .made(let url):
                // ShareLink rather than a save button: where a file should go is
                // the reader's business, and the share sheet already knows every
                // answer including "into Files".
                ShareLink(item: url) {
                    Text("Save or send the file")
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.onLamp)
                        .frame(maxWidth: .infinity, minHeight: ArchSpacing.minimumTapTarget)
                        .background(
                            RoundedRectangle(cornerRadius: ArchRadius.control,
                                             style: .continuous)
                                .fill(ArchColor.lamp)
                        )
                }
                ArchTextButton(title: "Build it again", action: build)

            case .failed(let why):
                Text(why)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.dataFailed")
                ArchButton(title: "Try again", kind: .quiet, action: build)
            }
        }
    }

    /// One of the four things Arch holds, as a line.
    ///
    /// Restored after I replaced this struct's body and took its helper with it.
    /// Swift does not say "no such function" for this one: `line` collides with
    /// the `#line` macro, so the error is "expansion of macro 'line()' requires
    /// leading '#'", which points at the call rather than the deletion.
    private func line(_ text: String) -> some View {
        Text(text)
            .archText(.body)
            .foregroundStyle(ArchColor.limestone)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func build() {
        stage = .working
        Task { @MainActor in
            do {
                let data = try await ArchBackend.myData()
                // Not an empty or broken answer saved as if it were the file.
                guard !data.isEmpty,
                      (try? JSONSerialization.jsonObject(with: data)) != nil else {
                    stage = .failed("Arch got an empty answer. Try again in a moment.")
                    return
                }
                // Written where the share sheet can reach it. A temporary
                // directory is right: this is a copy of what the server already
                // holds, and leaving copies of somebody's messages lying around
                // the device is the opposite of what this screen is for.
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Arch data.json")
                try data.write(to: url, options: .atomic)
                stage = .made(url)
            } catch {
                // Says what went wrong, so "it doesn't work" can be fixed.
                stage = .failed("Couldn\u{2019}t make the file: \(error.localizedDescription)")
            }
        }
    }
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

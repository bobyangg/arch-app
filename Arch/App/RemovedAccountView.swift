import SwiftUI

/// The screen for somebody who is no longer a user.
///
/// It replaces the whole app — no tabs, nothing to go back to — because there is
/// nothing left to navigate.
///
/// **How much to say is the whole design problem.** Say too little and it is a
/// blank wall, which is badly off-voice for an app that explains everything it
/// does. Say too much and it teaches an evader which signal tripped, and edges
/// toward naming who reported them. So it names the *category* and never the
/// evidence, and it never says how many people reported or when.
///
/// **No red, no icon, no alarm.** This is bad news delivered plainly, in the same
/// register as deleting your own account. Dressing it as a hazard would be the app
/// performing its own disapproval.
struct RemovedAccountView: View {
    let removal: Removal
    /// Where a reply would go. Sign in with Apple's relay address is fine.
    var email: String = "sam@example.com"
    var onAppeal: (String) -> Void = { _ in }
    /// Not part of the design — the prototype needs a way back out.
    var onLeave: (() -> Void)?

    @State private var isAppealing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: ArchSpacing.sectionGap)

            Text(title)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            Text(opening)
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                ForEach(consequences, id: \.self) { line in
                    Text(line)
                        .archText(.body)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, ArchSpacing.xl)

            Spacer(minLength: ArchSpacing.xl)

            appealSection

            if let onLeave {
                Button(action: onLeave) {
                    Text("Prototype only: back to the app")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, ArchSpacing.m)
                }
                .buttonStyle(PressScaleStyle(scale: 1))
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.night)
        .sheet(isPresented: $isAppealing) {
            AppealSheet { text in
                isAppealing = false
                onAppeal(text)
            } onCancel: {
                isAppealing = false
            }
        }
    }

    // MARK: The appeal

    @ViewBuilder
    private var appealSection: some View {
        switch removal.appeal {
        case .notSent:
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                // On the device screen this is the line the screen exists for.
                // Phones change hands, and the person holding this one may have
                // had nothing to do with it.
                if case .device = removal.kind {
                    Text("If this device was not yours then, say so. A person will read it.")
                        .archText(.body)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ArchButton(title: "Appeal this", kind: .quiet) { isAppealing = true }

                Text("One person reads every appeal. Nothing about this changes while they do.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .sent:
            VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                Text("Your appeal is with us")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                Text("A person will read it, usually within a couple of days, and you will hear back at \(email). Nothing changes until then.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .answered:
            VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                Text("A person read your appeal")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                Text("The decision stands, and there is no second appeal. If something has changed since, help@arch.app still reaches a person.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Words

    private var title: String {
        switch removal.kind {
        case .removed:             return "Your account has been removed"
        case .paused(let until):   return "Your account is paused until \(until)"
        case .device:              return "Arch cannot make an account on this device"
        }
    }

    private var opening: String {
        switch removal.kind {
        case .removed:
            return "Arch removed it after \(removal.reason.sentence)."
        case .paused:
            return "Arch paused it after \(removal.reason.sentence). Nothing is deleted."
        case .device:
            return "An account made on this device was removed for breaking the rules. That decision covers the device, not only the account."
        }
    }

    private var consequences: [String] {
        switch removal.kind {
        case .removed:
            return [
                "Your profile, photos and answers are deleted.",
                "The conversations you were in have ended. The people in them are not told why.",
                "You cannot make another account."
            ]
        case .paused:
            return [
                "Your profile is hidden until then. Nothing is deleted.",
                "Your conversations are waiting where you left them.",
                "It comes back on its own. There is nothing to do."
            ]
        case .device:
            return [
                "Nothing of yours was deleted, because nothing of yours was made."
            ]
        }
    }
}

/// Writing the appeal.
///
/// One field and a person, not a form of dropdowns — the app already promises that
/// reports go to a person rather than a filter, and an appeal that went to a filter
/// would make that promise look like a slogan.
///
/// **It refuses to imply the account is coming back.** Saying most appeals are not
/// overturned is the kind of thing that feels unkind to write and is kinder than the
/// alternative, which is somebody waiting on a decision that was never likely.
struct AppealSheet: View {
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isWriting: Bool

    private let characterLimit = 1000

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text("Tell us what we got wrong")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.l)

            Text("One person reads every appeal, usually within a couple of days.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                "",
                text: $text,
                prompt: Text("What do you think we missed?").foregroundColor(ArchColor.mortar),
                axis: .vertical
            )
            .archText(.callout)
            .foregroundStyle(ArchColor.limestone)
            .focused($isWriting)
            .lineLimit(5...10)
            .padding(ArchSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(ArchColor.night)
            )
            .onChange(of: text) { _, new in
                if new.count > characterLimit { text = String(new.prefix(characterLimit)) }
            }

            Spacer(minLength: 0)

            ArchButton(title: "Send", isEnabled: !trimmed.isEmpty) { onSend(trimmed) }

            Text("Your account stays as it is while this is read. Appealing does not undo it, and most appeals are not overturned.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            ArchTextButton(title: "Cancel", action: onCancel)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
        .onAppear { isWriting = true }
    }
}

// MARK: - Previews

#Preview("Removed") {
    RemovedAccountView(removal: Removal(kind: .removed, reason: .abuse))
        .preferredColorScheme(.dark)
}

#Preview("Paused until a date") {
    RemovedAccountView(removal: Removal(kind: .paused(until: "14 March"), reason: .selling))
        .preferredColorScheme(.dark)
}

/// The one the screen exists for. Somebody who bought this phone second-hand sees
/// it, and has done nothing at all.
#Preview("Blocked at signup") {
    RemovedAccountView(removal: Removal(kind: .device, reason: .abuse))
        .preferredColorScheme(.dark)
}

#Preview("Appeal waiting") {
    RemovedAccountView(
        removal: Removal(kind: .removed, reason: .photos, appeal: .sent)
    )
    .preferredColorScheme(.dark)
}

#Preview("Appeal answered") {
    RemovedAccountView(
        removal: Removal(kind: .removed, reason: .photos, appeal: .answered)
    )
    .preferredColorScheme(.dark)
}

#Preview("Writing an appeal") {
    AppealSheet(onSend: { _ in }, onCancel: {})
        .frame(height: 560)
        .preferredColorScheme(.dark)
}

import SwiftUI

/// The three things you can do about a person from inside a conversation.
///
/// Threaded as one value rather than three closures, because both the roster and
/// the messages list push threads and neither should have to know the difference.
struct ConversationActions {
    var leave: (Conversation) -> Void = { _ in }
    var block: (Person) -> Void = { _ in }
    /// person, reason, and whether to block them as well.
    var report: (Person, String, Bool) -> Void = { _, _, _ in }
}

/// What the reader is doing about this conversation, if anything.
enum ConversationAction: String, Identifiable {
    case menu, block, report, leave
    var id: String { rawValue }
}

// MARK: - The menu

/// A sheet rather than a system `Menu`.
///
/// Two reasons. A native menu arrives with its own greys and rounded corners, which
/// would be the only piece of system chrome in the app. And all three of these are
/// consequential enough to deserve a line explaining what they do — a menu row
/// cannot carry that, so people guess, and guessing about blocking is bad.
struct ConversationMenuSheet: View {
    let person: Person
    /// False once they have already left your roster, which changes what leaving costs.
    let isInRoster: Bool
    let onChoose: (ConversationAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            option(
                .report,
                title: "Report \(person.name)",
                detail: "Reports go to a person, not a filter."
            )
            option(
                .block,
                title: "Block \(person.name)",
                detail: "They stop seeing you and stop appearing again. They are not told."
            )
            option(
                .leave,
                title: "Leave this conversation",
                detail: isInRoster
                    ? "Removes the conversation, and takes \(person.name) out of your five."
                    : "Removes the conversation."
            )
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.xs)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchColor.stone)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
    }

    private func option(_ action: ConversationAction, title: String, detail: String) -> some View {
        Button { onChoose(action) } label: {
            VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                Text(title)
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                Text(detail)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(ArchColor.stoneRaised)
            )
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
    }
}

// MARK: - Block

/// Blocking is the strongest thing here, so it says every consequence including
/// the one people actually want to know: whether the other person finds out.
struct BlockConfirmSheet: View {
    let person: Person
    let isInRoster: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Block \(person.name)?")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xl)

            Text(detail)
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            Spacer(minLength: ArchSpacing.xl)

            ArchButton(title: "Block \(person.name)", kind: .quiet, action: onConfirm)
            ArchTextButton(title: "Cancel", action: onCancel)
                .padding(.top, ArchSpacing.xxs)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchColor.stone)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
    }

    private var detail: String {
        let roster = isInRoster ? "\(person.name) leaves your five, and " : ""
        return roster
            + "the conversation is removed. \(person.name) will not appear again and will not see you. "
            + "\(person.name) is not told. You can undo this in Settings."
    }
}

// MARK: - Report

/// Reporting is the one destructive-looking action the app actively wants you to
/// take, so it is the one that gets `lamp`. Blocking and leaving do not.
struct ReportSheet: View {
    let person: Person
    let onSend: (String, Bool) -> Void
    let onCancel: () -> Void

    @State private var reason: String?
    @State private var alsoBlock = true
    @State private var sent = false

    static let reasons = [
        "They were abusive or harassing",
        "Their photos are not them",
        "They are underage",
        "They are trying to sell something",
        "Something else"
    ]

    var body: some View {
        Group {
            if sent { confirmation } else { form }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .presentationDetents([.height(sent ? 320 : 620)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
    }

    /// Closing the loop. A report that disappears with no acknowledgement teaches
    /// people that reporting does nothing, which is the opposite of what it is for.
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Report sent")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xl)

            Text(alsoBlock
                 ? "A person will read it within a day, with the conversation attached. \(person.name) has been blocked and is not told about either."
                 : "A person will read it within a day, with the conversation attached. \(person.name) is not told.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            ArchButton(title: "Done") { onSend(reason ?? "", alsoBlock) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("Report \(person.name)")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                Text("A person reads every report, with this conversation attached. You do not need to explain twice.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, ArchSpacing.l)

            VStack(spacing: ArchSpacing.xs) {
                ForEach(Self.reasons, id: \.self) { option in
                    OptionRow(text: option, isSelected: reason == option) {
                        reason = option
                    }
                }
            }

            Toggle(isOn: $alsoBlock) {
                Text("Block \(person.name) as well")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
            }
            .tint(ArchColor.lamp)

            Spacer(minLength: 0)

            ArchButton(title: "Send report", isEnabled: reason != nil) {
                withAnimation(ArchMotion.standard) { sent = true }
            }
            ArchTextButton(title: "Cancel", action: onCancel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Leave

/// Leaving names the slot it costs, because otherwise it reads as tidying up a
/// list and it is not — leaving takes them out of your five too.
struct LeaveConfirmSheet: View {
    let person: Person
    let isInRoster: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Leave this conversation?")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xl)

            Text(detail)
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            Spacer(minLength: ArchSpacing.xl)

            ArchButton(title: "Leave", kind: .quiet, action: onConfirm)
            ArchTextButton(title: "Cancel", action: onCancel)
                .padding(.top, ArchSpacing.xxs)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchColor.stone)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
    }

    private var detail: String {
        isInRoster
            ? "The conversation is removed and \(person.name) leaves your five. That slot fills with someone new tomorrow. You cannot undo this."
            : "The conversation is removed. You cannot undo this."
    }
}

// MARK: - Previews

#Preview("Menu") {
    ConversationMenuSheet(person: MockData.nadia, isInRoster: true) { _ in }
        .frame(height: 280)
        .preferredColorScheme(.dark)
}

#Preview("Block") {
    BlockConfirmSheet(person: MockData.nadia, isInRoster: true, onConfirm: {}, onCancel: {})
        .frame(height: 320)
        .preferredColorScheme(.dark)
}

#Preview("Report") {
    ReportSheet(person: MockData.nadia, onSend: { _, _ in }, onCancel: {})
        .frame(height: 620)
        .preferredColorScheme(.dark)
}

#Preview("Leave") {
    LeaveConfirmSheet(person: MockData.nadia, isInRoster: true, onConfirm: {}, onCancel: {})
        .frame(height: 300)
        .preferredColorScheme(.dark)
}

#Preview("Leave, no longer in your five") {
    LeaveConfirmSheet(person: MockData.hana, isInRoster: false, onConfirm: {}, onCancel: {})
        .frame(height: 300)
        .preferredColorScheme(.dark)
}

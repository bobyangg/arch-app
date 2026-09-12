import SwiftUI

/// A conversation.
///
/// The photo or answer the first message was about stays pinned at the top, so
/// neither person has to scroll back to remember why they started talking.
///
/// Bubbles carry no colour — outgoing on `stoneRaised`, incoming on `stone`, both
/// in `limestone`. Position and surface lightness say who is speaking, which is
/// enough.
///
/// **No read receipts, and nothing about their phone.** What the other person has
/// done with your message is between them and their device, and "delivered" is a
/// quiet presence signal — it says their phone is on and online, which is the same
/// class of thing as the green dot Arch does not have.
///
/// Your own end of the wire is different, and the app owes you the truth about it:
/// a bad connection means a message can sit there looking sent when it never left.
/// So the last message you wrote says whether it got out, and the ones above it go
/// back to being timestamps — a column of "Sent" down the whole thread is clutter
/// answering a question nobody is still asking.
struct MessageThreadView: View {
    let conversation: Conversation
    /// Whether this person is still holding one of your slots, which changes what
    /// leaving and blocking cost.
    var isInRoster: Bool = false
    var actions = ConversationActions()
    var onAccept: (Conversation) -> Void = { _ in }
    var onDecline: (Conversation) -> Void = { _ in }
    var onRetry: (Message) -> Void = { _ in }

    @State private var draft = ""
    @State private var action: ConversationAction?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            switch conversation.state {
            case .request: requestBar
            case .ended:   endedBar
            case .open:    composer
            }
        }
        .background(ArchColor.night)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $action) { which in
            sheet(for: which)
        }
    }

    // MARK: The menu

    @ViewBuilder
    private func sheet(for which: ConversationAction) -> some View {
        switch which {
        case .menu:
            ConversationMenuSheet(person: conversation.person, isInRoster: isInRoster) { chosen in
                // Swap sheets on the next tick so the first one finishes leaving.
                action = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    action = chosen
                }
            }
        case .block:
            BlockConfirmSheet(person: conversation.person, isInRoster: isInRoster) {
                action = nil
                actions.block(conversation.person)
                dismiss()
            } onCancel: { action = nil }
        case .report:
            ReportSheet(person: conversation.person) { reason, alsoBlock in
                action = nil
                actions.report(conversation.person, reason, alsoBlock)
                dismiss()
            } onCancel: { action = nil }
        case .leave:
            LeaveConfirmSheet(person: conversation.person, isInRoster: isInRoster) {
                action = nil
                actions.leave(conversation)
                dismiss()
            } onCancel: { action = nil }
        }
    }

    // MARK: Pieces

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
            .accessibilityLabel("Back")

            PhotoPlaceholder(toneIndex: conversation.person.avatarToneIndex)
                .frame(width: 32, height: 32)
                .clipShape(Circle())

            Text(conversation.person.name)
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: 0)

            Button { action = .menu } label: {
                Image(systemName: "ellipsis")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.mortar)
                    .frame(
                        width: ArchSpacing.minimumTapTarget,
                        height: ArchSpacing.minimumTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Report, block, or leave")
        }
        .padding(.leading, ArchSpacing.xs)
        .padding(.trailing, ArchSpacing.xs)
        .padding(.bottom, ArchSpacing.xs)
        .background(ArchColor.night)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
    }

    private var lastOutgoing: Message? {
        conversation.messages.last { $0.isOutgoing }
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                if let opening = conversation.opening {
                    QuotedBlock(item: opening)
                        .padding(.bottom, ArchSpacing.m)
                }

                ForEach(conversation.messages) { message in
                    MessageBubble(
                        message: message,
                        // Only the last thing you wrote is still in question.
                        showsDelivery: message.id == lastOutgoing?.id,
                        onRetry: { onRetry(message) }
                    )
                }
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.vertical, ArchSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.bottom)
    }

    /// A request is read before it is answered, so the input bar is replaced by the
    /// decision. Accepting is the encouraged action and takes `lamp`; declining is
    /// quiet, and they are not told either way.
    private var requestBar: some View {
        VStack(spacing: ArchSpacing.xs) {
            Text("\(conversation.person.name) wrote to you. Answering moves this into your messages.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: ArchSpacing.xs) {
                ArchButton(title: "Decline", kind: .quiet) { onDecline(conversation) }
                ArchButton(title: "Answer") { onAccept(conversation) }
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.s)
        .padding(.bottom, ArchSpacing.xs)
        .background(ArchColor.stoneRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
    }

    /// The end of a conversation, with no account of itself.
    ///
    /// It says what you can do rather than what happened, and it ties itself to the
    /// rule the reader already knows from the roster — otherwise an unexplained
    /// ending is an invitation to assume the worst one.
    private var endedBar: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
            Text("This conversation has ended")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)

            Text("You can read it, but not reply. Arch does not say why a conversation ends, the same way it never says who left your roster.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.vertical, ArchSpacing.s)
        .background(ArchColor.stoneRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: ArchSpacing.xs) {
            TextField("Message", text: $draft, axis: .vertical)
                .archText(.callout)
                .foregroundStyle(ArchColor.limestone)
                .lineLimit(1...5)
                .padding(.horizontal, ArchSpacing.s)
                .padding(.vertical, ArchSpacing.xs + 2)
                .background(
                    RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                        .fill(ArchColor.stone)
                )

            Button { draft = "" } label: {
                Image(systemName: "arrow.up")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.night)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(ArchColor.lamp))
                    .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
            }
            .buttonStyle(PressScaleStyle())
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.vertical, ArchSpacing.xs)
        .background(ArchColor.stoneRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
    }
}

struct MessageBubble: View {
    let message: Message
    /// True for the last message you sent, which is the only one whose fate is
    /// still an open question.
    var showsDelivery: Bool = false
    var onRetry: () -> Void = {}

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: ArchSpacing.xxxl) }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: ArchSpacing.xxs) {
                Text(message.text)
                    .archText(.callout)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ArchSpacing.s + 2)
                    .padding(.vertical, ArchSpacing.xs + 2)
                    .background(
                        RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                            .fill(message.isOutgoing ? ArchColor.stoneRaised : ArchColor.stone)
                    )
                // The failure replaces the timestamp rather than sitting beside
                // it. "9:14 · Not sent" reads as a message that was sent at 9:14.
                if message.delivery == .failed {
                    Button(action: onRetry) {
                        Text("Not sent. Tap to try again.")
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.mortar)
                            .padding(.horizontal, ArchSpacing.xxs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle(scale: 1))
                } else {
                    Text(footnote)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .padding(.horizontal, ArchSpacing.xxs)
                }
            }
            // Held back while it is in the air, and again once it is clear it is
            // not going anywhere. No red: the network is not the reader's fault.
            .opacity(message.delivery == .sent ? 1 : 0.55)

            if !message.isOutgoing { Spacer(minLength: ArchSpacing.xxxl) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    /// "Sending" while it is in the air, "Sent" once it is out, and the timestamp
    /// for everything that is no longer a question.
    private var footnote: String {
        guard message.isOutgoing, showsDelivery else { return message.timestamp }
        switch message.delivery {
        case .sending: return "Sending"
        case .sent:    return "Sent"
        case .failed:  return message.timestamp
        }
    }

    private var label: String {
        let who = message.isOutgoing ? "You" : "Them"
        switch message.delivery {
        case .sent:    return "\(who): \(message.text)"
        case .sending: return "\(who): \(message.text). Sending."
        case .failed:  return "\(who): \(message.text). Not sent. Tap to try again."
        }
    }
}

// MARK: - Previews

/// Ended from their side. Which of the three things they did is not on this
/// screen, and that is the point.
#Preview("A conversation that ended") {
    NavigationStack {
        MessageThreadView(conversation: MockData.conversations[3])
    }
    .preferredColorScheme(.dark)
}

#Preview("Thread") {
    NavigationStack {
        MessageThreadView(conversation: MockData.conversations[0])
    }
    .preferredColorScheme(.dark)
}

/// One in the air and one that never left.
#Preview("A message that did not send") {
    NavigationStack {
        MessageThreadView(conversation: MockData.conversationWithFailure)
    }
    .preferredColorScheme(.dark)
}

#Preview("A request") {
    NavigationStack {
        MessageThreadView(conversation: MockData.conversations[0])
    }
    .preferredColorScheme(.dark)
}

#Preview("Thread, just started") {
    NavigationStack {
        MessageThreadView(
            conversation: Conversation(
                id: "c-new",
                person: MockData.priya,
                opening: .prompt(MockData.priya.prompts[0]),
                messages: [
                    Message(
                        id: "m-new",
                        text: "Three days later, still sitting there — I have absolutely done this with a message I spent twenty minutes on. What was the last one you found?",
                        isOutgoing: true,
                        timestamp: "Just now"
                    )
                ],
                unreadCount: 0,
                lastActivity: "Just now"
            )
        )
    }
    .preferredColorScheme(.dark)
}

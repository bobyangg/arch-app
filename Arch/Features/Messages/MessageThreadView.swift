import SwiftUI

/// A conversation.
///
/// The photo or answer the first message was about stays pinned at the top, so
/// neither person has to scroll back to remember why they started talking.
///
/// Bubbles carry no colour — outgoing on `stoneRaised`, incoming on `stone`, both
/// in `limestone`. Position and surface lightness say who is speaking, which is
/// enough. There are no read receipts and no delivery state.
struct MessageThreadView: View {
    let conversation: Conversation

    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            composer
        }
        .background(ArchColor.night)
        .toolbar(.hidden, for: .navigationBar)
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
        }
        .padding(.leading, ArchSpacing.xs)
        .padding(.trailing, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.xs)
        .background(ArchColor.night)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                if let opening = conversation.opening {
                    QuotedBlock(item: opening)
                        .padding(.bottom, ArchSpacing.m)
                }

                ForEach(conversation.messages) { message in
                    MessageBubble(message: message)
                }
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.vertical, ArchSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.bottom)
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
                Text(message.timestamp)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.horizontal, ArchSpacing.xxs)
            }

            if !message.isOutgoing { Spacer(minLength: ArchSpacing.xxxl) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.isOutgoing ? "You" : "Them"): \(message.text)")
    }
}

// MARK: - Previews

#Preview("Thread") {
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

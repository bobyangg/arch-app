import SwiftUI

/// Your conversations.
///
/// There is no "new connections" section. That belonged to the match model, where
/// a connection existed before anyone had said anything — in Arch a conversation
/// starts because somebody wrote a message, so a conversation and a message are the
/// same event.
///
/// One list, most recent first. Deliberately **no "waiting for a reply" grouping**:
/// separating the messages nobody answered would tell you that you have been passed
/// over, which the app has no business doing and often would not even be true.
struct MessagesListView: View {
    /// Conversations you are in. Requests are separate.
    let conversations: [Conversation]
    var requests: [Conversation] = []
    var onAccept: (Conversation) -> Void = { _ in }
    var onDecline: (Conversation) -> Void = { _ in }
    /// Sends the reader to their five, from the empty state.
    var onOpenDaily: () -> Void = {}
    var actions = ConversationActions()
    /// Whether a person still holds one of your slots.
    var holdsSlot: (Person) -> Bool = { _ in false }

    // NavigationPath, not [Conversation]: the requests folder pushes a different
    // type into this same stack.
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if conversations.isEmpty && requests.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(ArchColor.night)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Conversation.self) { conversation in
                MessageThreadView(
                    conversation: conversation,
                    isInRoster: holdsSlot(conversation.person),
                    actions: actions,
                    onAccept: { path = NavigationPath(); onAccept($0) },
                    onDecline: { path = NavigationPath(); onDecline($0) }
                )
            }
            .navigationDestination(for: RequestsRoute.self) { _ in
                MessageRequestsView(
                    requests: requests,
                    onOpen: { path.append($0) },
                    onAccept: onAccept,
                    onDecline: onDecline
                )
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Messages")
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)
                    .padding(.top, ArchSpacing.m)
                    .padding(.bottom, ArchSpacing.l)

                requestsFolder

                ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                    Button { path.append(conversation) } label: {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(PressScaleStyle(scale: 1))

                    if index < conversations.count - 1 {
                        Rectangle()
                            .fill(ArchColor.hairline)
                            .frame(height: ArchSpacing.hairline)
                            .padding(.leading, 52 + ArchSpacing.s)
                    }
                }
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.sectionGap)
        }
        .scrollIndicators(.hidden)
    }

    /// Requests sit above the conversations rather than mixed into them. Somebody
    /// you have not answered is a different kind of thing from somebody you are
    /// talking to, and a list that blends the two makes both harder to read.
    @ViewBuilder
    private var requestsFolder: some View {
        if !requests.isEmpty {
            NavigationLink(value: RequestsRoute()) {
                HStack(spacing: ArchSpacing.s) {
                    Text("Requests")
                        .archText(.body)
                        .foregroundStyle(ArchColor.limestone)
                    Spacer(minLength: 0)
                    UnreadBadge(count: requests.count)
                    Image(systemName: "chevron.right")
                        .archText(.caption)
                        .foregroundStyle(ArchColor.mortar)
                }
                .padding(ArchSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                        .fill(ArchColor.stone)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 1))
            .padding(.bottom, ArchSpacing.l)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Spacer()
            Text("No conversations yet")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
            Text("When you write to someone in your roster, the conversation appears here.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
            ArchButton(title: "Open your roster", kind: .quiet, action: onOpenDaily)
                .padding(.top, ArchSpacing.m)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One conversation.
///
/// Carries a name, what was last said, and when. No online dot, no last-active
/// time, no read state — none of which exist in Arch.
struct ConversationRow: View {
    let conversation: Conversation

    private var isUnread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: ArchSpacing.s) {
            PhotoPlaceholder(toneIndex: conversation.person.avatarToneIndex)
                .frame(width: 52, height: 52)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: ArchSpacing.xs) {
                    Text(conversation.person.name)
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    Spacer(minLength: 0)
                    Text(conversation.lastActivity)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                }

                HStack(alignment: .top, spacing: ArchSpacing.xs) {
                    Text(conversation.preview)
                        .archText(.footnote)
                        .foregroundStyle(isUnread ? ArchColor.limestone : ArchColor.mortar)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if isUnread {
                        Circle()
                            .fill(ArchColor.lamp)
                            .frame(width: 8, height: 8)
                            .padding(.top, ArchSpacing.xxs + 1)
                    }
                }
            }
        }
        .padding(.vertical, ArchSpacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(conversation.person.name), \(conversation.lastActivity)"
            + (isUnread ? ", unread" : "")
            + ". \(conversation.preview)"
        )
    }
}

// MARK: - Previews

#Preview("Messages") {
    MessagesListView(conversations: MockData.conversations)
        .preferredColorScheme(.dark)
}

#Preview("Messages, empty") {
    MessagesListView(conversations: [])
        .preferredColorScheme(.dark)
}

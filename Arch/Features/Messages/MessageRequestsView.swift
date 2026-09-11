import SwiftUI

/// The route value for the requests folder.
struct RequestsRoute: Hashable {}

/// People who have written to you and are waiting for an answer.
///
/// Kept out of the conversation list on purpose. Somebody you have not answered is
/// a different kind of thing from somebody you are talking to, and a list that
/// blends the two makes both harder to read — you lose track of who is actually
/// waiting on you.
///
/// Requests do not count towards the ten-conversation limit. You have not kept
/// anyone waiting by not answering yet; that is what this screen is for.
struct MessageRequestsView: View {
    let requests: [Conversation]
    let onOpen: (Conversation) -> Void
    let onAccept: (Conversation) -> Void
    let onDecline: (Conversation) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            if requests.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: ArchSpacing.m) {
                        ForEach(requests) { request in
                            card(request)
                        }
                    }
                    .padding(.horizontal, ArchSpacing.screenMargin)
                    .padding(.top, ArchSpacing.l)
                    .padding(.bottom, ArchSpacing.sectionGap)
                }
                .scrollIndicators(.hidden)
            }
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
            .accessibilityLabel("Back to messages")

            Text("Requests")
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

    private var empty: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Spacer()
            Text("Nothing waiting")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
            Text("When somebody in your five writes to you first, their message waits here until you answer it.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The whole message, not a one-line preview.
    ///
    /// You are being asked to decide about this person, and deciding from forty
    /// truncated characters is how you end up declining somebody who wrote something
    /// worth reading.
    private func card(_ request: Conversation) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Button { onOpen(request) } label: {
                VStack(alignment: .leading, spacing: ArchSpacing.s) {
                    HStack(spacing: ArchSpacing.s) {
                        PhotoPlaceholder(toneIndex: request.person.avatarToneIndex)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 0) {
                            Text(request.person.name)
                                .archText(.subhead)
                                .foregroundStyle(ArchColor.limestone)
                            Text(request.person.location)
                                .archText(.footnote)
                                .foregroundStyle(ArchColor.mortar)
                        }

                        Spacer(minLength: 0)

                        Text(request.lastActivity)
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.mortar)
                    }

                    if let opening = request.opening {
                        QuotedBlock(item: opening)
                    }

                    Text(request.preview)
                        .archText(.callout)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PressScaleStyle(scale: 1))

            HStack(spacing: ArchSpacing.xs) {
                ArchButton(title: "Decline", kind: .quiet) { onDecline(request) }
                ArchButton(title: "Answer") { onAccept(request) }
            }
        }
        .padding(ArchSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
    }
}

#Preview("Requests") {
    NavigationStack {
        MessageRequestsView(
            requests: MockData.conversations.filter { $0.state == .request },
            onOpen: { _ in },
            onAccept: { _ in },
            onDecline: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Requests, empty") {
    NavigationStack {
        MessageRequestsView(requests: [], onOpen: { _ in }, onAccept: { _ in }, onDecline: { _ in })
    }
    .preferredColorScheme(.dark)
}

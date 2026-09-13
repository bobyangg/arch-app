import SwiftUI

/// The roster: your five slots, people first, open slots grouped underneath.
///
/// There is no completion state and nothing to work through. Doing nothing is a
/// perfectly good outcome — a person stays in your five indefinitely if neither of
/// you acts — so the screen never asks you to clear anything.
struct DailyFiveView: View {
    let roster: Roster
    /// How many conversations are open, which decides whether the roster is shown.
    var conversationCount: Int = 0
    /// Ten, or fifteen with premium. Passed in rather than read from a static,
    /// because it is no longer the same number for everybody.
    var conversationLimit: Int = DailyFiveStore.freeConversations
    /// Sends the reader to Messages from the held state.
    var onOpenMessages: () -> Void = {}
    /// Paused in Discovery settings. The people already here stay; only the
    /// refilling stops.
    var isPaused: Bool = false
    var onUnpause: () -> Void = {}
    /// Only so the empty state can tell the truth. An empty roster and a roster
    /// that never arrived looked identical, and the empty one says "nothing here
    /// needs fixing" — which is a reassuring sentence and, offline, a lie.
    var isOffline: Bool = false
    let onDismiss: (Person) -> Void
    let onSend: (Person, String, ProfileItem?) -> Conversation
    var actions = ConversationActions()

    @State private var path: [Route] = []
    @State private var pendingDismissal: Person?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Route: Hashable {
        case profile(Person)
        case thread(Conversation)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if isHeld {
                        heldNotice
                    } else {
                        approachingNotice
                        people
                        if isPaused {
                            pausedNotice
                        } else if roster.people.isEmpty {
                            emptyNotice
                        } else {
                            openSlots
                        }
                    }
                }
                .padding(.horizontal, ArchSpacing.screenMargin)
                .padding(.bottom, ArchSpacing.sectionGap)
            }
            .background(ArchColor.night)
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .profile(let person):
                    ProfileDetailView(
                        person: person,
                        conversationCount: conversationCount,
                        conversationLimit: conversationLimit,
                        onDismiss: { pendingDismissal = person },
                        onSend: { text, item in
                            let conversation = onSend(person, text, item)
                            path = [.thread(conversation)]
                        }
                    )
                case .thread(let conversation):
                    MessageThreadView(
                        conversation: conversation,
                        isInRoster: roster.people.contains { $0.id == conversation.person.id },
                        actions: actions
                    )
                }
            }
        }
        .sheet(item: $pendingDismissal) { person in
            DismissConfirmSheet(
                rosterName: roster.name,
                person: person,
                onConfirm: {
                    pendingDismissal = nil
                    // If we are looking at their profile, come back to the roster
                    // before the card goes, so nothing disappears under the cursor.
                    path.removeAll()
                    onDismiss(person)
                },
                onCancel: { pendingDismissal = nil }
            )
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text(roster.title)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)

            // Left-aligned, not centred: the header reads as one block, and the
            // stones fill from the same edge the text starts at.
            ArchSlotIndicator(filled: roster.filledCount, capacity: roster.capacity)

            Rectangle()
                .fill(ArchColor.hairline)
                .frame(height: ArchSpacing.hairline)
        }
        .padding(.top, ArchSpacing.m)
        .padding(.bottom, ArchSpacing.xl)
    }

    private var isHeld: Bool { conversationCount >= conversationLimit }
    private var warnFrom: Int { conversationLimit - 2 }

    /// Not an error and not a telling-off. The people are still yours, the rule is
    /// stated once, and the way out is a button rather than a lecture.
    private var heldNotice: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("\(roster.title) are waiting")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Text("You have \(conversationCount) conversations open. Arch holds the people in your roster until you are back under \(conversationLimit) — leave a conversation you are not going to answer and they come straight back.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            ArchButton(title: "Open your messages", kind: .quiet, action: onOpenMessages)
                .padding(.top, ArchSpacing.m)
        }
        .padding(.bottom, ArchSpacing.sectionGap)
    }

    /// Paused.
    ///
    /// The roster above is untouched — the people already in it are still yours,
    /// and a pause that threw them away would be a punishment for taking a break.
    /// Only the part that refills is replaced.
    ///
    /// Nothing is greyed out. Greying is what an error looks like, and this is a
    /// thing you chose on purpose.
    private var pausedNotice: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Rectangle()
                .fill(ArchColor.hairline)
                .frame(height: ArchSpacing.hairline)
                .padding(.bottom, ArchSpacing.m)
                .padding(.top, roster.people.isEmpty ? 0 : ArchSpacing.sectionGap)

            Text("Your profile is paused")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Text("Nobody new will arrive, and you are not in anyone else's roster. Your conversations are not affected.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            ArchButton(title: "Unpause", kind: .quiet, action: onUnpause)
                .padding(.top, ArchSpacing.m)
        }
    }

    /// Nothing here at all.
    ///
    /// Five identical open-slot cards stacked up is what the general case produces
    /// and it reads as five separate pieces of bad news. One sentence is the whole
    /// state — and on the first morning it is not bad news at all.
    private var emptyNotice: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text(isOffline
                 ? "Arch could not load your roster"
                 : roster.isFirstMorning
                   ? "Your first five arrive in the morning"
                   : "All \(ArchCopy.word(roster.capacity)) slots are open")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            Text(isOffline
                 ? "This is a connection, not your roster. Whoever is in it is still in it."
                 : roster.isFirstMorning
                   ? "Arch is choosing them overnight. There is nothing to do until then — it is not a queue and there is no way to hurry it."
                   : "Everyone's five arrive at the same moment, first thing. Nothing here needs fixing.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One line, only in the last two. Said early enough to be useful and late
    /// enough not to nag.
    @ViewBuilder
    private var approachingNotice: some View {
        if conversationCount >= warnFrom {
            let left = conversationLimit - conversationCount
            Text(left == 1
                 ? "One more conversation and your roster will wait until you leave one."
                 : "\(left) more conversations and your roster will wait until you leave one.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, ArchSpacing.xl)
        }
    }

    private var people: some View {
        VStack(spacing: ArchSpacing.cardGap) {
            ForEach(roster.people) { person in
                RosterCard(
                    person: person,
                    onOpen: { path.append(.profile(person)) },
                    onDismiss: { pendingDismissal = person }
                )
                .transition(.opacity)
            }
        }
        .animation(
            ArchMotion.honouring(reduceMotion, ArchMotion.cardCollapse),
            value: roster.people
        )
    }

    @ViewBuilder
    private var openSlots: some View {
        let slots = roster.openSlots
        if !slots.isEmpty {
            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                Rectangle()
                    .fill(ArchColor.hairline)
                    .frame(height: ArchSpacing.hairline)
                    .padding(.top, roster.people.isEmpty ? 0 : ArchSpacing.sectionGap)

                Text("New people arrive in these slots.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.bottom, ArchSpacing.xxs)

                ForEach(slots) { slot in
                    if let refillsAt = slot.refillsAt {
                        EmptySlotCard(
                            refillsAt: refillsAt,
                            opening: slot.opening,
                            rosterName: roster.name
                        )
                            .transition(.opacity)
                    }
                }
            }
            .animation(
                ArchMotion.honouring(reduceMotion, ArchMotion.slotOpens),
                value: roster.openSlots
            )
        }
    }
}

// MARK: - Previews

#Preview("Full") {
    DailyFivePreview(roster: MockData.rosterFull)
}

#Preview("Partial") {
    DailyFivePreview(roster: MockData.rosterPartial)
}

#Preview("Nearly empty") {
    DailyFivePreview(roster: MockData.rosterNearlyEmpty)
}

#Preview("The first morning") {
    DailyFivePreview(roster: MockData.rosterFirstMorning)
}

#Preview("Everybody gone") {
    DailyFivePreview(roster: MockData.rosterEmpty)
}

/// Offline with nothing loaded. The sentence that used to sit here said nothing
/// needed fixing, which was the wrong thing to say to somebody in a tunnel.
#Preview("Offline, nothing loaded") {
    DailyFiveView(
        roster: MockData.rosterEmpty,
        isOffline: true,
        onDismiss: { _ in },
        onSend: { _, _, _ in MockData.conversations[0] }
    )
    .preferredColorScheme(.dark)
}

#Preview("Paused") {
    DailyFiveView(
        roster: MockData.rosterFull,
        isPaused: true,
        onDismiss: { _ in },
        onSend: { _, _, _ in MockData.conversations[0] }
    )
    .preferredColorScheme(.dark)
}

/// Paused with nothing in the roster — the two notices must not both appear.
#Preview("Paused and empty") {
    DailyFiveView(
        roster: MockData.rosterEmpty,
        isPaused: true,
        onDismiss: { _ in },
        onSend: { _, _, _ in MockData.conversations[0] }
    )
    .preferredColorScheme(.dark)
}

#Preview("Held at ten conversations") {
    DailyFiveView(
        roster: MockData.rosterFull,
        conversationCount: 10,
        onDismiss: { _ in },
        onSend: { _, _, _ in MockData.conversations[0] }
    )
    .preferredColorScheme(.dark)
}

#Preview("One away from the limit") {
    DailyFiveView(
        roster: MockData.rosterFull,
        conversationCount: 9,
        onDismiss: { _ in },
        onSend: { _, _, _ in MockData.conversations[0] }
    )
    .preferredColorScheme(.dark)
}

/// Wires a live store in, so dismissing in the preview actually drops a stone.
private struct DailyFivePreview: View {
    @State private var store: DailyFiveStore

    init(roster: Roster) {
        _store = State(initialValue: DailyFiveStore(roster: roster))
    }

    var body: some View {
        DailyFiveView(
            roster: store.roster,
            onDismiss: { store.dismiss($0) },
            onSend: { store.startConversation(with: $0, text: $1, quoting: $2) }
        )
        .preferredColorScheme(.dark)
    }
}

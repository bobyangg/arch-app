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
    /// Dismissed today and not gone until nine. Shown under the open slots,
    /// where they are out of the way of the decision they are no longer part of.
    var waiting: [Person] = []
    let onDismiss: (Person) -> Void
    var onRestore: (Person) -> Void = { _ in }
    let onSend: (Person, String, ProfileItem?) -> Conversation
    var actions = ConversationActions()

    /// Bumped by the shell when the tab already showing is tapped again. Every
    /// change means "back to the five"; the value itself means nothing.
    /// The current state of a conversation, by id.
    ///
    /// **A pushed value is a photograph.** `navigationDestination` hands back
    /// whatever was put on the path, so a thread opened a minute ago is the
    /// thread as it was a minute ago -- and a reply added to the store did not
    /// appear until you left the screen and came back. That was the whole of
    /// "I have to leave the chat to see what I sent".
    ///
    /// Looking it up on every render fixes it: the store is observed, so a
    /// change re-runs this body and the thread is rebuilt from what is there
    /// now. The pushed copy stays as the fallback, for a conversation that has
    /// left the store while somebody was reading it.
    var live: (String) -> Conversation? = { _ in nil }
    /// A reply in a thread opened from here.
    var onReply: (Conversation, String) -> Void = { _, _ in }
    var popToRoot: Int = 0

    /// The conversation on screen here, or nil. See `MessagesListView`.
    var onThreadOpenChanged: (String?) -> Void = { _ in }

    @State private var path: [Route] = []
    @State private var pendingDismissal: Person?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Route: Hashable {
        case profile(Person)
        case thread(Conversation)
    }

    var body: some View {
        NavigationStack(path: $path) {
            TopBarScroll {
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
                        waitingSection
                    }
                }
                .padding(.horizontal, ArchSpacing.screenMargin)
                .padding(.bottom, ArchSpacing.sectionGap)
            }
            .background(ArchColor.night)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .archBackSwipe()
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
                case .thread(let pushed):
                    let conversation = live(pushed.id) ?? pushed
                    MessageThreadView(
                        conversation: conversation,
                        isInRoster: roster.people.contains { $0.id == conversation.person.id },
                        actions: actions,
                        onOpenProfile: { path.append(.profile(conversation.person)) },
                        onSend: { onReply(conversation, $0) },
                        onOpenChanged: onThreadOpenChanged
                    )
                }
            }
        }
        // Tapping the tab you are already on returns it to the five. The You
        // and Messages tabs already did this; being in a profile and pressing
        // Daily 5 did nothing, which is the one place it is most obviously
        // meant to.
        .onChange(of: popToRoot) { _, _ in path = [] }
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
        }
        .padding(.top, ArchSpacing.m)
        // The gap does what a rule used to: the header is one block, the people
        // are another, and the air between them says so.
        .padding(.bottom, ArchSpacing.xxl)
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

            Text("You have \(conversationCount) conversations open. Arch holds your matches until you are back under \(conversationLimit). Leave a conversation you are not going to answer and they come straight back.")
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
            Text("Your profile is paused")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Text("Nobody new will arrive, and you are not in anyone else's match list. Your conversations are not affected.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            ArchButton(title: "Unpause", kind: .quiet, action: onUnpause)
                .padding(.top, ArchSpacing.m)
        }
        .padding(.top, roster.people.isEmpty ? 0 : ArchSpacing.sectionGap)
    }

    /// Nothing here at all.
    ///
    /// Five identical open-slot cards stacked up is what the general case produces
    /// and it reads as five separate pieces of bad news. One sentence is the whole
    /// state — and on the first morning it is not bad news at all.
    private var emptyNotice: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text(isOffline
                 ? "Arch could not load your matches"
                 : roster.isFirstMorning
                   ? "Your first five arrive in the morning"
                   : "All \(ArchCopy.word(roster.capacity)) spots are open")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            Text(isOffline
                 ? "This is a connection, not your match list. Whoever is in it is still in it."
                 : roster.isFirstMorning
                   ? "Arch is always looking for the right people for you. New matches are revealed at \(RefillCopy.batchHour()). If there is nothing yet, Arch is still searching."
                   : "People arrive at \(RefillCopy.batchHour()), wherever you are. Nothing here needs fixing.")
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
                 ? "One more conversation and your matches will wait until you leave one."
                 : "\(left) more conversations and your matches will wait until you leave one.")
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

    /// The people you dismissed today, until the morning takes them.
    ///
    /// Under the open slots rather than above them, because these are decisions
    /// already made and the slots are the part that is still about to happen.
    ///
    /// The heading says what will happen and not what you should do about it.
    /// Dismissing is meant to be a real decision, and an undo presented as a
    /// second chance would make it a question again every time you opened the
    /// tab — so this is stated once, flatly, with no count and no clock.
    @ViewBuilder
    private var waitingSection: some View {
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                Text("Leaving in the morning")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)

                Text("You dismissed these people. Nothing has happened yet — you can still write to them, or put them back.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, ArchSpacing.xxs)

                ForEach(waiting) { person in
                    WaitingCard(
                        person: person,
                        onOpen: { path.append(.profile(person)) },
                        onRestore: { onRestore(person) }
                    )
                    .transition(.opacity)
                }
            }
            .padding(.top, ArchSpacing.sectionGap)
            .animation(ArchMotion.honouring(reduceMotion, ArchMotion.slotOpens),
                       value: waiting)
        }
    }

    @ViewBuilder
    private var openSlots: some View {
        let slots = roster.openSlots
        if !slots.isEmpty {
            VStack(alignment: .leading, spacing: ArchSpacing.m) {
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
            .padding(.top, roster.people.isEmpty ? 0 : ArchSpacing.sectionGap)
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

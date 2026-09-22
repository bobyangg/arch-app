import Foundation
import Observation

/// Everything the Daily 5 knows. Views below `DailyFiveView` take plain values and
/// closures and never see this type, so the whole tree previews without it and the
/// mock source can be swapped for a real one here alone.
@Observable
final class DailyFiveStore {

    private(set) var roster: Roster
    private(set) var conversations: [Conversation]

    init(
        roster: Roster = MockData.rosterFull,
        conversations: [Conversation] = MockData.conversations
    ) {
        self.roster = roster
        self.conversations = conversations
    }

    /// Nine in the morning, New York time, for everybody at once.
    ///
    /// **Not nine wherever you happen to be.** Mutual pairing creates a pair for two
    /// people in the same instant, so rolling per-timezone batches would have to hand
    /// somebody a roster hours after theirs was already on screen, or reserve slots
    /// across runs and reconcile them afterwards. One batch makes that problem not
    /// exist, and it is a great deal less to run.
    ///
    /// Arch is open across the United States and Canada, so for most readers this
    /// is not the local nine: it is six in the morning in Vancouver and half past
    /// ten in St. John's. Nothing in the app claims otherwise — the open slot
    /// names the zone the hour belongs to rather than the reader's own.
    static let refillHour = 9

    /// The zone the batch runs in.
    ///
    /// An identifier and not a fixed offset: "EST" is UTC-5 all year, so for the
    /// seven months of daylight saving it would deliver at eight in the morning in
    /// the city it is named after. Landing in the morning is the whole point.
    static let refillZone = TimeZone(identifier: "America/New_York") ?? .gmt

    /// Something a write to the server could not do. Screens read this to say so.
    var lastError: ArchAPIError?

    /// Tonight's roster and every conversation, from the server.
    ///
    /// One call rather than one per screen: the tabs are three views over the same
    /// two collections, and loading them separately is how the roster and the
    /// message list end up disagreeing about whether somebody is still there.
    func load() async throws {
        guard ArchConfig.isConfigured else { return }
        let people = try await ArchBackend.roster()
        let threads = try await ArchBackend.conversations()

        // The slots the server did not fill are open, not missing. `capacity`
        // already knows about Premium.
        //
        // An open slot carries when it refills and *why* it is open — and the why
        // is always `.yours` here, because the server does not say. It cannot: a
        // slot that knew whether the other person left would be the app telling you
        // you were dismissed, which is the one thing it promises never to do.
        var slots = people.map { RosterSlot.filled($0) }
        let refill = Self.nextRefill()
        while slots.count < capacity {
            slots.append(.empty(id: "open-\(slots.count)",
                                refillsAt: refill,
                                opening: .yours))
        }
        roster = Roster(slots: Array(slots.prefix(capacity)),
                        isFirstMorning: people.isEmpty && threads.isEmpty)
        conversations = threads
        lastError = nil
    }

    /// Persist in the background. The local change has already happened, because
    /// dismissing somebody should not wait on a round trip.
    ///
    /// `@MainActor` on the task, not three `MainActor.run` closures inside it:
    /// `[weak self]` captures a mutable optional, and reading it from a closure
    /// nested inside the task is a data race that Swift 6 rejects outright.
    /// Isolating the continuation removes the inner closure entirely.
    private func persist(_ work: @escaping () async throws -> Void) {
        guard ArchConfig.isConfigured else { return }
        Task { @MainActor [weak self] in
            do {
                try await work()
                self?.lastError = nil
            } catch let error as ArchAPIError {
                self?.lastError = error
            } catch {
                self?.lastError = .transport
            }
        }
    }

    static let freeSlots = 5
    static let premiumSlots = 7
    /// Above this, the roster waits. The point is that people answer the
    /// conversations they start rather than collecting more of them.
    static let freeConversations = 10
    static let premiumConversations = 15

    /// Premium widens both limits. It does not change who Arch picks, how fast
    /// slots refill, or anything about who has looked at you.
    ///
    /// Set through `setSubscribed(_:)`, because the roster has to be resized in the
    /// same breath — a seven-slot subscriber with five slots on screen would be a
    /// feature the user paid for and cannot see.
    private(set) var isSubscribed = false

    func setSubscribed(_ value: Bool) {
        guard value != isSubscribed else { return }
        isSubscribed = value
        resizeRoster()
    }

    var capacity: Int { isSubscribed ? Self.premiumSlots : Self.freeSlots }
    var conversationLimit: Int { isSubscribed ? Self.premiumConversations : Self.freeConversations }
    /// Warn two conversations out, whichever limit applies.
    var warnFrom: Int { conversationLimit - 2 }

    var unreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    /// Conversations you are actually in. A request you have not answered is not
    /// something you are keeping someone waiting on, so it does not count.
    var openConversations: [Conversation] { conversations.filter { $0.state == .open } }

    /// People who have written to you and are waiting.
    /// Only the ones somebody sent *you*. A request you sent is in `threads`.
    var requests: [Conversation] {
        conversations.filter { $0.state == .request && !$0.openedByMe }
    }

    /// What the Messages list shows: everything open, plus the ones you have
    /// written and are waiting on.
    ///
    /// Deliberately not the same as `openConversations`, which stays the count
    /// the roster hold is computed from — the server works that out from
    /// `state = 'open'` alone, and the two have to agree or the app and the
    /// matcher disagree about whether you are full.
    var threads: [Conversation] {
        conversations.filter { $0.state == .open || ($0.state == .request && $0.openedByMe) }
    }

    /// Your people are still there and still yours — they are just not shown
    /// until you are back under the limit. Nothing is lost by waiting.
    var isRosterHeld: Bool { openConversations.count >= conversationLimit }

    /// Subscribing adds slots; cancelling takes them away.
    ///
    /// Empty slots go first, so cancelling never drops somebody who is still in
    /// your roster while a gap sits next to them.
    private func resizeRoster() {
        let target = capacity
        while roster.slots.count < target {
            roster.slots.append(
                .empty(
                    id: "slot-\(roster.slots.count + 1)-\(UUID().uuidString.prefix(4))",
                    refillsAt: Self.nextRefill(),
                    opening: .yours
                )
            )
        }
        while roster.slots.count > target {
            if let empty = roster.slots.lastIndex(where: { $0.person == nil }) {
                roster.slots.remove(at: empty)
            } else {
                roster.slots.removeLast()
            }
        }
    }

    /// Answering somebody is how a request becomes a conversation.
    func accept(_ conversation: Conversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[index].state = .open
        conversations[index].unreadCount = 0
        persist { try await ArchBackend.accept(conversation.id) }
    }

    /// Declining removes it. They are not told, the same as everything else here.
    func decline(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        persist { try await ArchBackend.end(conversation.id) }
    }

    /// Somebody wrote to you.
    ///
    /// Their message becomes a request and they leave your five — not as a cost,
    /// but because they have stopped being someone to consider and started being
    /// someone to answer. Holding them in both places would show them twice.
    func receive(_ conversation: Conversation) {
        conversations.insert(conversation, at: 0)
        dismiss(conversation.person, opening: .theirs)
    }

    /// Dismissing costs a slot until tomorrow. The person is replaced by an open
    /// slot in place; the screen groups open slots underneath the people.
    ///
    /// There is no undo, and nothing anywhere records who dismissed whom.
    func dismiss(_ person: Person, opening: SlotOpening = .yours) {
        guard let index = roster.slots.firstIndex(where: { $0.id == person.id }) else { return }
        roster.slots[index] = .empty(
            id: "slot-\(person.id)",
            refillsAt: Self.nextRefill(),
            opening: opening
        )
        persist { try await ArchBackend.dismiss(person) }
    }

    /// The first message.
    ///
    /// There is no match gate to clear first. Writing to someone **spends the
    /// slot they were in** — they leave your five and it fills with someone new
    /// tomorrow, the same as a dismissal. Messaging is what a slot is *for*, so
    /// spending one on a person you want to talk to is the system working, not a
    /// penalty.
    @discardableResult
    func startConversation(
        with person: Person,
        text: String,
        quoting item: ProfileItem?
    ) -> Conversation {
        if let existing = conversations.first(where: { $0.person.id == person.id }) {
            return existing
        }
        // **Shown at once and sent immediately after, and the sending is what
        // was missing.** `ArchBackend.startConversation` existed, was correct,
        // and had no callers: this built a conversation with an invented id,
        // put it in the list, and stopped. The message lived in memory on one
        // phone until the app closed. Nothing was written, so the other person
        // was never told, and the database held no conversations and no
        // messages at all.
        //
        // `request` rather than `open`, because that is the state
        // `start_conversation` creates and the reader should not see one thing
        // now and a different one after a refresh. `openedByMe` keeps it out of
        // your own requests folder.
        let conversation = Conversation(
            id: "pending-\(person.id)",
            person: person,
            state: .request,
            openedByMe: true,
            opening: item,
            messages: [
                Message(
                    id: "m-\(person.id)-1",
                    text: text,
                    isOutgoing: true,
                    timestamp: Date().formatted(.dateTime.hour().minute())
                )
            ],
            unreadCount: 0,
            lastActivity: "Just now"
        )
        conversations.insert(conversation, at: 0)
        // Writing to them spends the slot.
        dismiss(person)

        // The id the server gives back replaces the placeholder, because every
        // later call -- replying, leaving, ending -- is addressed by it. A
        // thread left holding `pending-` would fail every one of them.
        let placeholder = conversation.id
        persist { [weak self] in
            let id = try await ArchBackend.startConversation(with: person, body: text)
            await MainActor.run { self?.adopt(serverID: id, replacing: placeholder) }
        }
        return conversation
    }

    /// Swaps the placeholder id for the one the server assigned.
    @MainActor
    private func adopt(serverID: String, replacing placeholder: String) {
        guard let index = conversations.firstIndex(where: { $0.id == placeholder }) else { return }
        let old = conversations[index]
        conversations[index] = Conversation(
            id: serverID,
            person: old.person,
            state: old.state,
            openedByMe: old.openedByMe,
            opening: old.opening,
            messages: old.messages,
            unreadCount: old.unreadCount,
            lastActivity: old.lastActivity
        )
    }

    /// Leaving a conversation takes the person out of your five as well.
    ///
    /// Anything else would make it weightless: they would still hold a slot, could
    /// still write, and the conversation would come straight back. One action, both
    /// consequences, and the sheet says so before you tap it.
    func leave(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        dismiss(conversation.person)
        persist { try await ArchBackend.end(conversation.id) }
    }

    /// Blocking does everything leaving does, and stops them reaching you again.
    func block(_ person: Person) {
        conversations.removeAll { $0.person.id == person.id }
        dismiss(person)
        persist {
            try await ArchBackend.block(person)
            // The conversation ends too, and lands on the same state
            // leaving does -- if blocking looked different from here the
            // other person could tell the two apart.
            if let thread = self.conversations.first(where: { $0.person.id == person.id }) {
                try await ArchBackend.end(thread.id)
            }
        }
    }

    /// What the other side sees when somebody leaves, blocks, or deletes.
    ///
    /// Nothing calls this in a design build — there is no second phone to do the
    /// leaving — but it is the one mutation the real one needs, and writing it here
    /// keeps the state from being a fixture nobody can reach.
    func end(_ conversation: Conversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[index].state = .ended
        conversations[index].unreadCount = 0
        persist { try await ArchBackend.end(conversation.id) }
    }

    func holdsSlot(_ person: Person) -> Bool {
        roster.people.contains { $0.id == person.id }
    }

    /// The next batch, as an instant — not a rolling 24-hour timer from whenever the
    /// slot happened to open. The wait is a fact about tomorrow morning rather than a
    /// clock to watch.
    ///
    /// Computed in `refillZone` because that is where the job runs, and returned as a
    /// `Date`, which has no timezone of its own. The day is then read in the reader's
    /// calendar and the hour in the batch's zone, with its abbreviation — so somebody
    /// in London is told "tomorrow, 9am EST", which is true and says whose nine.
    private static func nextRefill(from now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = refillZone
        let next = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: refillHour, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
        return next ?? now.addingTimeInterval(24 * 60 * 60)
    }
}

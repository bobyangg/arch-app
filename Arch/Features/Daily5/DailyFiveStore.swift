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

    /// Everyone's five arrive at the same hour, in their own morning. The matching
    /// runs overnight in one batch — which is what makes mutual pairing possible at
    /// all — and the result is simply there when people wake up. Nobody experiences
    /// the hour it was computed.
    static let refillHour = 9

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
    var requests: [Conversation] { conversations.filter { $0.state == .request } }

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
    }

    /// Declining removes it. They are not told, the same as everything else here.
    func decline(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
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
        let conversation = Conversation(
            id: "c-\(person.id)",
            person: person,
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
        return conversation
    }

    /// Leaving a conversation takes the person out of your five as well.
    ///
    /// Anything else would make it weightless: they would still hold a slot, could
    /// still write, and the conversation would come straight back. One action, both
    /// consequences, and the sheet says so before you tap it.
    func leave(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        dismiss(conversation.person)
    }

    /// Blocking does everything leaving does, and stops them reaching you again.
    func block(_ person: Person) {
        conversations.removeAll { $0.person.id == person.id }
        dismiss(person)
    }

    func holdsSlot(_ person: Person) -> Bool {
        roster.people.contains { $0.id == person.id }
    }

    /// Tomorrow at `refillHour`, in the reader's own timezone — not a rolling
    /// 24-hour timer from whenever the slot happened to open. The wait is a fact
    /// about tomorrow morning rather than a clock to watch.
    private static func nextRefill(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(
            bySettingHour: refillHour, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
    }
}

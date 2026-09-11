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

    /// Above this, the roster waits. The point is that people reply to the
    /// conversations they start rather than collecting more of them.
    static let conversationLimit = 10
    /// How close to the limit before the roster warns you it is coming.
    static let warnFrom = 8

    var unreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    /// Your five are still there and still yours — they are just not shown until
    /// you are back under the limit. Nothing is lost by waiting.
    var isRosterHeld: Bool { conversations.count >= Self.conversationLimit }

    /// Dismissing costs a slot until tomorrow. The person is replaced by an open
    /// slot in place; the screen groups open slots underneath the people.
    ///
    /// There is no undo, and nothing anywhere records who dismissed whom.
    func dismiss(_ person: Person) {
        guard let index = roster.slots.firstIndex(where: { $0.id == person.id }) else { return }
        roster.slots[index] = .empty(id: "slot-\(person.id)", refillsAt: Self.nextRefill())
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

    /// New people arrive in the morning, not on a rolling 24-hour timer — so the
    /// wait is a fact about tomorrow rather than a clock the user watches.
    private static func nextRefill(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
    }
}

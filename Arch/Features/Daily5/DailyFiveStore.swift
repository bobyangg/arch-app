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

    var unreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    /// Dismissing costs a slot until tomorrow. The person is replaced by an open
    /// slot in place; the screen groups open slots underneath the people.
    ///
    /// There is no undo, and nothing anywhere records who dismissed whom.
    func dismiss(_ person: Person) {
        guard let index = roster.slots.firstIndex(where: { $0.id == person.id }) else { return }
        roster.slots[index] = .empty(id: "slot-\(person.id)", refillsAt: Self.nextRefill())
    }

    /// The first message. There is no match gate to clear first — if you want to
    /// talk to someone in your five, you write to them.
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
        return conversation
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

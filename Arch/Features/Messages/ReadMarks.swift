import Foundation

/// How far you have read in each conversation, on this phone.
///
/// **Yours, and nobody else's.** Arch has no read receipts: what you have read
/// is never sent anywhere, and the other person cannot find it out. That is why
/// this lives in `UserDefaults` rather than in the database -- the only screen
/// that needs it is yours, and a column would be a read receipt waiting to be
/// wired up.
///
/// A mark is the time of the newest message that was in the thread when you
/// were last in it. A message from them after that is new.
///
/// **The first launch reads everything up to then.** Without a mark, every
/// message ever received would count as new, and the first thing this would do
/// is put a badge on threads you finished weeks ago. So the first time it runs
/// it remembers the moment, and messages from before that are read.
struct ReadMarks {

    private let defaults: UserDefaults
    private static let marksKey = "arch.read.marks"
    private static let baselineKey = "arch.read.baseline"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.baselineKey) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: Self.baselineKey)
        }
    }

    private var baseline: Date {
        Date(timeIntervalSince1970: defaults.double(forKey: Self.baselineKey))
    }

    private var marks: [String: Double] {
        defaults.dictionary(forKey: Self.marksKey) as? [String: Double] ?? [:]
    }

    /// Read up to here.
    func readThrough(_ conversationID: String) -> Date {
        marks[conversationID].map(Date.init(timeIntervalSince1970:)) ?? baseline
    }

    /// Read up to `date`, and never backwards: a slower refresh that brings an
    /// older message cannot un-read a newer one.
    func markRead(_ conversationID: String, through date: Date) {
        var all = marks
        let current = all[conversationID] ?? 0
        all[conversationID] = max(current, date.timeIntervalSince1970)
        defaults.set(all, forKey: Self.marksKey)
    }

    /// Messages from them since you last read.
    func unread(in conversation: Conversation) -> Int {
        let since = readThrough(conversation.id)
        return conversation.messages.filter { message in
            !message.isOutgoing && (message.sentAt ?? .distantPast) > since
        }.count
    }
}

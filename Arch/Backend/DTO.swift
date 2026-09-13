import Foundation

/// The rows, exactly as the database returns them, and how they become the types
/// the app already draws.
///
/// Kept as a separate layer rather than making `Person` itself `Codable`, because
/// the two shapes genuinely differ and pretending otherwise leaks the database into
/// the views. The database stores a birthdate; the app shows an age. The database
/// stores centimetres; the app shows "6 ft 1". The database has a row per photo with
/// a storage path; the app has an ordered array.
///
/// It is also the seam that keeps a mistake from becoming a leak. `ProfileRow` has
/// no field for a questionnaire answer, so no amount of careless work upstream can
/// put one on screen — there is nowhere for it to land.

// MARK: - Profiles

/// What comes back for somebody else, from the `visible_profiles` view.
///
/// Note what is absent: birthdate, coordinates, compatibility score, questionnaire
/// answers, last-seen. The view does not select them and this type could not hold
/// them if it did.
struct ProfileRow: Decodable, Hashable {
    let accountId: String
    let name: String
    let age: Int
    let gender: String
    let pronouns: String?
    let placeId: String
    let heightCm: Int?
    let work: String?
}

/// Your own profile, which has the two extra fields you are allowed to see about
/// yourself because you typed them.
struct OwnProfileRow: Codable, Hashable {
    var accountId: String
    var name: String
    var birthdate: String          // ISO `yyyy-MM-dd`; never shown, only edited
    var gender: String
    var pronouns: String?
    var placeId: String
    var coarseLat: Double
    var coarseLon: Double
    var heightCm: Int?
    var work: String?
}

struct PhotoRow: Codable, Hashable, Identifiable {
    var id: String
    var accountId: String
    var position: Int
    var storagePath: String
    var state: String
    var rejectedReason: String?
}

struct PromptRow: Codable, Hashable, Identifiable {
    var id: String
    var accountId: String
    var position: Int
    var promptKey: String
    var answer: String
}

struct InterestRow: Codable, Hashable, Identifiable {
    var id: String
    var accountId: String
    var position: Int
    var text: String
}

// MARK: - Discovery

struct DiscoveryRow: Codable, Hashable {
    var accountId: String
    var seeking: [String]
    var distanceMiles: Int
    var minAge: Int
    var maxAge: Int
    var paused: Bool
    var notifyMessages: Bool
}

// MARK: - Pairing

struct PairingRow: Decodable, Hashable, Identifiable {
    let id: String
    let night: String
    let loAccount: String
    let hiAccount: String

    /// The other person, given who is asking.
    func other(than me: String) -> String { loAccount == me ? hiAccount : loAccount }
}

/// What the roster endpoint returns: the pairing joined to the profile, in one
/// round trip rather than one request per slot.
struct RosterEntryRow: Decodable, Hashable {
    let pairingId: String
    let night: String
    let profile: ProfileRow
    let photos: [PhotoRow]
    let prompts: [PromptRow]
    let interests: [InterestRow]
}

// MARK: - Conversations

struct ConversationRow: Decodable, Hashable, Identifiable {
    let id: String
    let loAccount: String
    let hiAccount: String
    let state: String
    let openedBy: String
    let lastMessageAt: Date?

    func other(than me: String) -> String { loAccount == me ? hiAccount : loAccount }
}

struct MessageRow: Codable, Hashable, Identifiable {
    var id: String
    var conversationId: String
    var senderId: String
    var body: String
    var createdAt: Date
}

/// What goes up when somebody writes. The id and timestamp are the server's to
/// decide, so they are absent here.
struct NewMessage: Encodable {
    let conversationId: String
    let senderId: String
    let body: String
}

// MARK: - Account

struct AccountRow: Decodable, Hashable {
    let id: String
    let status: String
    let appleEmail: String?
}

struct RemovalRow: Decodable, Hashable, Identifiable {
    let id: String
    let kind: String
    let reason: String
    let until: Date?
}

// MARK: - Mapping into the app's own types

extension ProfileRow {

    /// A row as the `Person` every screen already knows how to draw.
    ///
    /// Photos, prompts and interests arrive separately because they are separate
    /// tables; the roster endpoint fetches them together and hands them in here.
    func person(
        photos: [PhotoRow] = [],
        prompts: [PromptRow] = [],
        interests: [InterestRow] = []
    ) -> Person {
        Person(
            id: accountId,
            name: name,
            age: age,
            place: PlaceLibrary.place(matching: placeId),
            height: ArchUnits.height(fromCentimetres: heightCm),
            work: work ?? "",
            gender: ArchUnits.gender(fromColumn: gender),
            pronouns: pronouns ?? "",
            photos: photos.sorted { $0.position < $1.position }
                .enumerated()
                .map { index, row in Photo(id: row.id, toneIndex: index) },
            prompts: prompts.sorted { $0.position < $1.position }
                .map { Prompt(id: $0.id,
                              question: PromptLibrary.text(forID: $0.promptKey),
                              answer: $0.answer) },
            interests: interests.sorted { $0.position < $1.position }
                .map { Interest(id: $0.id, text: $0.text) }
        )
    }
}

extension ConversationRow {

    func conversation(with person: Person, messages: [MessageRow], me: String) -> Conversation {
        Conversation(
            id: id,
            person: person,
            state: ConversationState(rawValue: state) ?? .open,
            opening: nil,
            messages: messages.sorted { $0.createdAt < $1.createdAt }
                .map { row in
                    Message(
                        id: row.id,
                        text: row.body,
                        isOutgoing: row.senderId == me,
                        timestamp: ArchUnits.shortTime(row.createdAt),
                        delivery: .sent
                    )
                },
            // Arch has no read receipts, so "unread" is only ever about your own
            // side of the thread: messages that arrived after you last opened it.
            // That count is local, and is filled in by the store.
            unreadCount: 0,
            lastActivity: ArchUnits.relative(lastMessageAt)
        )
    }
}

/// Conversions the database does not do and the views should not have to.
enum ArchUnits {

    /// Centimetres to the string the height picker offers, so a profile shows the
    /// same wording whether it was just edited or just downloaded.
    static func height(fromCentimetres cm: Int?) -> String {
        guard let cm, cm > 0 else { return "" }
        let totalInches = Int((Double(cm) / 2.54).rounded())
        return "\(totalInches / 12) ft \(totalInches % 12)"
    }

    /// "6 ft 1" back to centimetres, for saving.
    static func centimetres(fromHeight text: String) -> Int? {
        let parts = text.split(whereSeparator: { !$0.isNumber })
        guard parts.count == 2,
              let feet = Int(parts[0]), let inches = Int(parts[1]) else { return nil }
        return Int((Double(feet * 12 + inches) * 2.54).rounded())
    }

    static func birthdate(fromAge age: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(byAdding: .year, value: -age, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func age(fromBirthdate iso: String, calendar: Calendar = .current) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: iso) else { return 0 }
        return calendar.dateComponents([.year], from: date, to: Date()).year ?? 0
    }

    static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    /// "Yesterday", "Tuesday", "3 March" — never "2 minutes ago", which turns a
    /// conversation into something to keep checking.
    static func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return shortTime(date) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateFormat = "d MMMM"
        }
        return formatter.string(from: date)
    }

    /// The app's `Gender` as the database's enum spelling, and back.
    static func genderColumn(_ gender: Gender) -> String {
        gender == .nonBinary ? "non_binary" : gender.rawValue
    }

    static func gender(fromColumn raw: String) -> Gender? {
        Gender(rawValue: raw == "non_binary" ? "nonBinary" : raw)
    }
}

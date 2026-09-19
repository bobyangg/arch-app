import Observation
import SwiftUI

/// Everything Settings can change.
///
/// The settings list is derived from this rather than from a static fixture, so a
/// row's detail line is the live value — change the distance and the row says so
/// when you come back.
@Observable
final class SettingsStore {

    // Account
    var email = "sam@example.com"
    var isSubscribed = false

    // Notifications
    /// What iOS has decided, which is not the same thing as what you want.
    /// When this is false the three switches below cannot do anything, so they are
    /// not shown pretending to.
    var systemNotificationsAllowed = true
    /// The only notification Arch sends.
    ///
    /// There were three switches — the morning roster, new people, and messages —
    /// against an onboarding screen promising "two kinds, and nothing else". Two of
    /// the three fired at the same moment for the same reason, because slots only
    /// ever refill at nine.
    ///
    /// It is one now, and the two that went were both the app telling you to come
    /// back. Your roster is there when you open it; a person writing to you is the
    /// only thing that has any business interrupting your day.
    var messageAlert = true

    // Discovery
    /// A requirement rather than a preference: nobody outside it reaches you.
    /// Discovery settings, from the server.
    ///
    /// The defaults above are what a design build shows and what a brand-new
    /// account gets; this replaces them once there is somewhere to read from.
    func load() async throws {
        guard ArchConfig.isConfigured else { return }
        guard let row = try await ArchBackend.discovery() else { return }
        seeking = Set(row.seeking.compactMap { ArchUnits.gender(fromColumn: $0) })
        distance = row.distanceMiles
        minAge = row.minAge
        maxAge = row.maxAge
        isPaused = row.paused
        messageAlert = row.notifyMessages

        let rows = try await ArchBackend.answers()
        answers = Dictionary(rows.map { ($0.questionId, $0.optionIndex) }, uniquingKeysWith: { $1 })
        answersAnsweredAt = rows.map(\.answeredAt).max()
    }

    /// Written whole rather than field by field. Every one of these is a filter the
    /// matcher reads tonight, and a half-written set is a roster built to settings
    /// nobody chose.
    func save() {
        guard ArchConfig.isConfigured else { return }
        Task { [seeking, distance, minAge, maxAge, isPaused, messageAlert] in
            guard let session = await SupabaseClient.shared.restore() else { return }
            try? await ArchBackend.saveDiscovery(
                DiscoveryRow(
                    accountId: session.userID,
                    seeking: seeking.map { ArchUnits.genderColumn($0) },
                    distanceMiles: distance,
                    minAge: minAge,
                    maxAge: maxAge,
                    paused: isPaused,
                    notifyMessages: messageAlert
                )
            )
        }
    }

    var seeking: Set<Gender> = [.man, .woman, .nonBinary]
    /// Twenty-five miles, not ten. Ten reached most of four boroughs and was a
    /// sensible default while New York was the whole app; across the US and
    /// Canada it is a radius that finds nobody outside a metro, and an empty
    /// roster is the one failure the product does not survive.
    var distance = 25
    var minAge = 26
    var maxAge = 36
    var lookingFor = "Something serious"
    var isPaused = false

    // The questionnaire

    /// What you said, by question id, as the index of the option -- the same
    /// shape the server keeps, so a reword of an option cannot move an answer.
    var answers: [String: Int] = [:]
    /// When you last answered, whether in onboarding or again from Settings.
    /// Nil until the server has said, or in a design build, where there is no
    /// server and the wait is therefore never applied.
    var answersAnsweredAt: Date?

    /// How long between one set of answers and the next, without Premium.
    ///
    /// Thirty days, and the reason is not upsell. The matcher pairs on these
    /// answers every night, and an answer that changes every evening is not a
    /// fact about somebody, it is a mood -- and the people it puts in front of
    /// you tomorrow were chosen against the mood. A month is long enough for
    /// an answer to have been true. Premium waives it on the reasoning that
    /// somebody paying for the app is not gaming it.
    static let answerAgainWait: TimeInterval = 30 * 24 * 60 * 60

    /// When answering again opens up, or nil if it is open now.
    var answerAgainAvailableOn: Date? {
        guard !isSubscribed, let last = answersAnsweredAt else { return nil }
        let opens = last.addingTimeInterval(Self.answerAgainWait)
        return opens > .now ? opens : nil
    }
    var canAnswerAgain: Bool { answerAgainAvailableOn == nil }

    /// Written whole, like everything else the matcher reads.
    func saveAnswers(_ chosen: [String: Int]) {
        answers = chosen
        answersAnsweredAt = .now
        guard ArchConfig.isConfigured else { return }
        Task { [chosen] in
            try? await ArchBackend.saveAnswers(chosen)
        }
    }

    // Privacy
    var blocked: [String] = []

    // Appearance

    /// Light, dark, or whatever the phone is doing.
    ///
    /// Written straight back to `UserDefaults`, because the app root reads the same
    /// key through `@AppStorage` and there is no store between them — onboarding and
    /// the removal screen are outside this object's reach but inside the app's.
    var theme: ArchTheme = ArchTheme(
        rawValue: UserDefaults.standard.string(forKey: ArchTheme.storageKey) ?? ""
    ) ?? .system {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: ArchTheme.storageKey) }
    }

    /// Five to a hundred, and the top of the slider means anywhere.
    ///
    /// It started at one mile, which promised a precision Arch does not have and
    /// does not want: a location is kept to about a kilometre, and somebody who
    /// declined and picked a place instead is only as precise as that place is
    /// wide. Five is comfortably above both.
    ///
    /// A mile was never the right floor for this app anyway. Distance here is a
    /// "could we plausibly meet" filter, not a proximity feature — Arch picks five
    /// people on compatibility and never sorts or shows anybody by how near they
    /// are.
    static let distanceRange = 5...100
    /// The top of the range stops being a number: somebody in a small town needs
    /// no ceiling at all, and they are the people a radius starves first.
    static func isUnlimited(_ distance: Int) -> Bool { distance >= distanceRange.upperBound }
    static let ageRange = 18...70
    static let intentions = ["Something serious", "Still working it out", "Something casual"]

    // MARK: Display

    var distanceText: String {
        Self.isUnlimited(distance) ? "Anywhere" : "Within \(distance) miles"
    }
    var ageText: String { "\(minAge) to \(maxAge)" }
    var premiumText: String { isSubscribed ? "Subscribed" : "Not subscribed" }
    /// What to call the roster in settings copy, which has no roster to read.
    /// The same word `Roster.name` derives from the slots themselves.
    var rosterName: String { isSubscribed ? "your seven" : "your five" }
    var rosterTitle: String { isSubscribed ? "Your seven" : "Your five" }
    var seekingText: String { Gender.sentence(seeking) }
    /// The row says so, so that pausing does not need a second screen to be legible.
    var pausedText: String? { isPaused ? "Paused" : nil }
    var blockedText: String { blocked.isEmpty ? "None" : "\(blocked.count)" }
    /// When you last answered, as a date on the row. Nothing until it is known.
    var answersText: String? {
        answersAnsweredAt.map { "Answered " + $0.formatted(.dateTime.day().month()) }
    }

    /// The whole list, rebuilt from current values.
    ///
    /// Toggles sit *in* the row. A row that pushes somewhere gets a chevron and a
    /// row that flips gets a switch — never both, and never a switch hidden behind
    /// a push.
    var sections: [SettingsSection] { sections(place: nil) }

    /// `place` is the label on the profile, which this store does not hold; the
    /// screen that has the profile passes it in so the row can say where you are.
    func sections(place: String?) -> [SettingsSection] {
        var notifications: [SettingsRow] = []
        if systemNotificationsAllowed {
            notifications.append(.init(id: "n-msg", title: "Messages", control: .toggle(messageAlert)))
        } else {
            // Three switches that cannot do anything are worse than one row that
            // says why. This is the only place in Settings a row stands in for a
            // group, and it is because iOS has taken the group away.
            notifications.append(
                .init(id: "n-blocked", title: "Notifications are off",
                      detail: "In your iPhone settings", control: .push)
            )
        }

        return [
            SettingsSection(id: "account", title: "Account", rows: [
                .init(id: "a-email", title: "Email", detail: email, control: .push),
                .init(id: "a-premium", title: "Arch Premium", detail: premiumText, control: .push),
                .init(id: "a-delete", title: "Delete your account", control: .push)
            ]),
            SettingsSection(
                id: "notifications", title: "Notifications", rows: notifications,
                // The only setting in the app that had no explanation, because a
                // toggle row has no detail page to put one on. What it sends is
                // also the thing worth saying plainly: the name and the words, so
                // somebody can decide whether to open it without opening it.
                note: systemNotificationsAllowed
                    ? "Every message gets one. It shows who wrote to you and what they said, so you can decide whether to open it. Arch sends nothing else — no reminders, and nothing about your five."
                    : nil
            ),
            SettingsSection(id: "appearance", title: "Appearance", rows: [
                .init(id: "x-theme", title: "Light and dark", detail: theme.title, control: .push)
            ]),
            SettingsSection(id: "discovery", title: "Discovery", rows: [
                .init(id: "d-location", title: "Where you are", detail: place, control: .push),
                .init(id: "d-seeking", title: "Who you want to meet", detail: seekingText, control: .push),
                .init(id: "d-distance", title: "Distance", detail: distanceText, control: .push),
                .init(id: "d-age", title: "Age range", detail: ageText, control: .push),
                .init(id: "d-intent", title: "Looking for", detail: lookingFor, control: .push),
                .init(id: "d-answers", title: "Your answers", detail: answersText, control: .push),
                .init(id: "d-pause", title: "Pause my profile", detail: pausedText, control: .toggle(isPaused))
            ]),
            // "Who can see me" was here, with two options. The first was what
            // Arch does anyway and the second was never wired to anything, so
            // the row was a choice between the default and a promise. Pausing
            // is the one real control over being seen, and it is in Discovery.
            SettingsSection(id: "privacy", title: "Privacy", rows: [
                .init(id: "p-blocked", title: "Blocked people", detail: blockedText, control: .push),
                .init(id: "p-data", title: "Download your data", control: .push)
            ]),
            SettingsSection(id: "help", title: "Help", rows: [
                .init(id: "h-how", title: "How Arch works", control: .push),
                .init(id: "h-safety", title: "Safety", control: .push),
                .init(id: "h-contact", title: "Contact us", control: .push)
            ])
        ]
    }

    func toggle(_ id: String) {
        switch id {
        case "n-msg":   messageAlert.toggle()
        case "d-pause": isPaused.toggle()
        default: break
        }
    }

    /// Never empties. A preference for nobody is not a preference, and the row
    /// would silently stop matching anyone with nothing on screen saying why.
    func toggleSeeking(_ gender: Gender) {
        if seeking.contains(gender) {
            guard seeking.count > 1 else { return }
            seeking.remove(gender)
        } else {
            seeking.insert(gender)
        }
    }

    func isOn(_ id: String) -> Bool {
        switch id {
        case "n-msg":   return messageAlert
        case "d-pause": return isPaused
        default: return false
        }
    }
}

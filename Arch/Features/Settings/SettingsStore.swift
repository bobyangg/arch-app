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
    var phone = "+1 (917) 555 0142"
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
    var seeking: Set<Gender> = [.man, .woman, .nonBinary]
    var distance = 10
    var minAge = 26
    var maxAge = 36
    var lookingFor = "Something serious"
    var isPaused = false

    // Privacy
    var visibility = "Anyone Arch picks me for"
    var blocked: [String] = []

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
    static let visibilities = ["Anyone Arch picks me for", "Nobody new while I have unread messages"]

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

    /// The whole list, rebuilt from current values.
    ///
    /// Toggles sit *in* the row. A row that pushes somewhere gets a chevron and a
    /// row that flips gets a switch — never both, and never a switch hidden behind
    /// a push.
    var sections: [SettingsSection] {
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
                .init(id: "a-phone", title: "Phone number", detail: phone, control: .push),
                .init(id: "a-email", title: "Email", detail: email, control: .push),
                .init(id: "a-premium", title: "Arch Premium", detail: premiumText, control: .push),
                .init(id: "a-delete", title: "Delete your account", control: .push)
            ]),
            SettingsSection(id: "notifications", title: "Notifications", rows: notifications),
            SettingsSection(id: "discovery", title: "Discovery", rows: [
                .init(id: "d-seeking", title: "Who you want to meet", detail: seekingText, control: .push),
                .init(id: "d-distance", title: "Distance", detail: distanceText, control: .push),
                .init(id: "d-age", title: "Age range", detail: ageText, control: .push),
                .init(id: "d-intent", title: "Looking for", detail: lookingFor, control: .push),
                .init(id: "d-pause", title: "Pause my profile", detail: pausedText, control: .toggle(isPaused))
            ]),
            SettingsSection(id: "privacy", title: "Privacy", rows: [
                .init(id: "p-visible", title: "Who can see me", detail: visibility, control: .push),
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

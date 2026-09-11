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
    var dailyFiveAlert = true
    var dailyFiveTime = "9:00"
    var newPeopleAlert = true
    var messageAlert = true

    // Discovery
    var distance = 10
    var minAge = 26
    var maxAge = 36
    var lookingFor = "Something serious"
    var isPaused = false

    // Privacy
    var visibility = "Anyone Arch picks me for"
    var blocked: [String] = []

    static let distanceRange = 1...50
    static let ageRange = 18...70
    static let intentions = ["Something serious", "Still working it out", "Something casual"]
    static let visibilities = ["Anyone Arch picks me for", "Nobody new while I have unread messages"]
    static let times = ["7:00", "8:00", "9:00", "10:00", "12:00", "18:00"]

    // MARK: Display

    var distanceText: String { "Within \(distance) miles" }
    var ageText: String { "\(minAge) to \(maxAge)" }
    var premiumText: String { isSubscribed ? "Subscribed" : "Not subscribed" }
    /// What to call the roster in settings copy, which has no roster to read.
    /// The same word `Roster.name` derives from the slots themselves.
    var rosterName: String { isSubscribed ? "your seven" : "your five" }
    var rosterTitle: String { isSubscribed ? "Your seven" : "Your five" }
    var blockedText: String { blocked.isEmpty ? "None" : "\(blocked.count)" }

    /// The whole list, rebuilt from current values.
    ///
    /// Toggles sit *in* the row. A row that pushes somewhere gets a chevron and a
    /// row that flips gets a switch — never both, and never a switch hidden behind
    /// a push.
    var sections: [SettingsSection] {
        var notifications: [SettingsRow] = [
            .init(id: "n-daily", title: "Your daily five", control: .toggle(dailyFiveAlert))
        ]
        // The time only exists if the notification does.
        if dailyFiveAlert {
            notifications.append(.init(id: "n-time", title: "Time", detail: dailyFiveTime, control: .push))
        }
        notifications.append(.init(id: "n-new", title: "New people", control: .toggle(newPeopleAlert)))
        notifications.append(.init(id: "n-msg", title: "Messages", control: .toggle(messageAlert)))

        return [
            SettingsSection(id: "account", title: "Account", rows: [
                .init(id: "a-phone", title: "Phone number", detail: phone, control: .push),
                .init(id: "a-email", title: "Email", detail: email, control: .push),
                .init(id: "a-premium", title: "Arch Premium", detail: premiumText, control: .push)
            ]),
            SettingsSection(id: "notifications", title: "Notifications", rows: notifications),
            SettingsSection(id: "discovery", title: "Discovery", rows: [
                .init(id: "d-distance", title: "Distance", detail: distanceText, control: .push),
                .init(id: "d-age", title: "Age range", detail: ageText, control: .push),
                .init(id: "d-intent", title: "Looking for", detail: lookingFor, control: .push),
                .init(id: "d-pause", title: "Pause my profile", control: .toggle(isPaused))
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
        case "n-daily": dailyFiveAlert.toggle()
        case "n-new":   newPeopleAlert.toggle()
        case "n-msg":   messageAlert.toggle()
        case "d-pause": isPaused.toggle()
        default: break
        }
    }

    func isOn(_ id: String) -> Bool {
        switch id {
        case "n-daily": return dailyFiveAlert
        case "n-new":   return newPeopleAlert
        case "n-msg":   return messageAlert
        case "d-pause": return isPaused
        default: return false
        }
    }
}

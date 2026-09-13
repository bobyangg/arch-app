import SwiftUI

/// Which of the two worlds the app is in.
///
/// Arch was a dark app, and dark is still what it looks like at nine in the
/// evening when the roster is the last thing you check. But a dating app is also
/// read on a train at eight in the morning, and a reader who keeps their phone in
/// light mode should not be handed a black screen for it.
///
/// `system` is the default and is what almost everybody will stay on. The other
/// two exist because the people who care about this care about it a lot, and
/// because "follow my phone" is not an answer for someone whose phone is set
/// wrong for the room they are in.
enum ArchTheme: String, CaseIterable, Identifiable {
    /// Whatever iOS is doing.
    case system
    /// Candlelight. Paper in morning sun.
    case light
    /// Rich Charcoal. The same room at night.
    case dark

    /// Where the choice is kept. A display preference belongs to the device rather
    /// than to the account: the phone that is set to light mode is the phone that
    /// should open in it, whoever is signed in.
    static let storageKey = "arch.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match my phone"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var note: String {
        switch self {
        case .system: return "Follows your iPhone's appearance setting."
        case .light:  return "Candlelight. Paper, warm ink, terracotta."
        case .dark:   return "Rich charcoal. The same palette after dark."
        }
    }

    /// Nil hands the decision back to iOS, which is the point of `system`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

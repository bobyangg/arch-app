import SwiftUI

/// A slot waiting for tomorrow.
///
/// An open slot is the system working, not a failure, so this card is *quieter*
/// than a person's card and about a quarter its height. It states two facts and
/// stops. No dashed border — dashed reads as "add something here", which would make
/// an open slot the user's problem to fix.
///
/// There is exactly one variant. Whether you dismissed them or they dismissed you,
/// the slot looks identical, because the app never tells you which happened.
struct EmptySlotCard: View {
    let refillsAt: Date
    /// Whether you opened this slot or they did.
    var opening: SlotOpening = .yours
    /// "your five", or "your seven" with premium.
    var rosterName: String = "your five"

    var body: some View {
        VStack(spacing: ArchSpacing.xxs) {
            // Said when they went, never who and never why. Writing to you and
            // dismissing you both land here, so this line cannot be read backwards
            // into "you were rejected".
            if opening == .theirs {
                Text("Someone left \(rosterName).")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
            }
            Text(RefillCopy.headline(for: refillsAt))
                .archText(opening == .theirs ? .footnote : .body)
                .foregroundStyle(opening == .theirs ? ArchColor.mortar : ArchColor.limestone)
            Text(RefillCopy.detail(for: refillsAt))
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.photo, style: .continuous)
                .fill(ArchColor.stone)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ArchRadius.photo, style: .continuous)
                .strokeBorder(ArchColor.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Copy for the refill time.
///
/// Deliberately coarse. An exact countdown would manufacture urgency around a wait
/// the user cannot do anything about, and a ticking clock is ambient motion. Hours,
/// then days, computed when the view appears.
enum RefillCopy {

    static func headline(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(date) {
            return "A new person arrives tomorrow."
        }
        if calendar.isDateInToday(date) {
            return "A new person arrives later today."
        }
        let weekday = date.formatted(.dateTime.weekday(.wide))
        return "A new person arrives on \(weekday)."
    }

    static func detail(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let hours = Int((seconds / 3600).rounded())

        if hours < 1 { return "Within the hour" }
        if hours == 1 { return "About an hour" }
        if hours < 48 { return "About \(hours) hours" }

        let days = Int((seconds / 86_400).rounded())
        return "About \(days) days"
    }
}

#Preview("Open slots") {
    VStack(spacing: ArchSpacing.m) {
        EmptySlotCard(refillsAt: Date().addingTimeInterval(14 * 3600))
        EmptySlotCard(refillsAt: Date().addingTimeInterval(38 * 3600))
        EmptySlotCard(refillsAt: Date().addingTimeInterval(62 * 3600))
        EmptySlotCard(refillsAt: Date().addingTimeInterval(14 * 3600), opening: .theirs)
    }
    .padding(.horizontal, ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

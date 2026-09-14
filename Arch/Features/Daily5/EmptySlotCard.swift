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
/// The day in the reader's own calendar, and the hour in the batch's own zone. No
/// countdown: an exact one would manufacture urgency around a wait the user cannot
/// do anything about, and a ticking clock is ambient motion.
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

    /// "9am EST", or "9am EDT" for the seven months New York is on daylight time.
    /// The abbreviation comes from the zone for that date rather than being written
    /// down, so the card cannot name an hour the batch does not run at.
    static func detail(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DailyFiveStore.refillZone
        return label(hour24: calendar.component(.hour, from: date), on: date)
    }

    /// The batch hour as of today, for copy that talks about the batch in general
    /// rather than about one slot's next refill.
    static func batchHour(now: Date = Date()) -> String {
        label(hour24: DailyFiveStore.refillHour, on: now)
    }

    private static func label(hour24: Int, on date: Date) -> String {
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let meridiem = hour24 < 12 ? "am" : "pm"
        let abbreviation = DailyFiveStore.refillZone.abbreviation(for: date) ?? "ET"
        return "\(hour12)\(meridiem) \(abbreviation)"
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

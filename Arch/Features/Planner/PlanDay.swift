import Foundation

/// The day a date is on: a calendar date with no time attached, written
/// "2026-10-10" wherever it is stored or sent.
///
/// A date and not a `Date`. A `Date` is an instant, and an instant becomes a
/// different day in a different time zone; a plan for Saturday has to stay
/// Saturday on both phones, so what travels is the day itself, and each phone
/// reads it in its own calendar.
///
/// **From tomorrow, up to three months ahead.** Not today: Arch is
/// deliberately unhurried, and a plan made with somebody you have only been
/// writing to is not a plan for tonight. It was a week, offered as a row of
/// seven; a calendar lets a date be planned around a concert or a holiday, and
/// three months is as far as anybody plans a date with somebody new.
struct PlanDay: Hashable, Identifiable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    var id: String { iso }

    /// "2026-10-10". Zero-padded, so comparing two as strings orders them.
    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    /// Nil for anything that is not a real day written the way `iso` writes it.
    init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        // A day that does not exist -- the 31st of September -- is refused
        // rather than rolled over into October.
        guard components.isValidDate(in: Calendar(identifier: .gregorian)) else { return nil }
        year = parts[0]
        month = parts[1]
        day = parts[2]
    }

    static var today: PlanDay { PlanDay(.now) }

    /// How far ahead a date can be planned, in days.
    static let daysAhead = 90

    /// The first day the planner offers: tomorrow.
    static func earliest(from now: Date = .now, calendar: Calendar = .current) -> PlanDay {
        PlanDay(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now,
                calendar: calendar)
    }

    /// The last day the planner offers.
    static func latest(from now: Date = .now, calendar: Calendar = .current) -> PlanDay {
        PlanDay(calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: now)) ?? now,
                calendar: calendar)
    }

    /// The days from tomorrow, for as many as are asked for. Used where a few
    /// upcoming days are wanted by weekday, such as the design build's plans.
    static func upcoming(_ count: Int = 7, from now: Date = .now,
                         calendar: Calendar = .current) -> [PlanDay] {
        let start = calendar.startOfDay(for: now)
        return (1...max(count, 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { PlanDay($0, calendar: calendar) }
        }
    }

    /// Whether this day can be planned for now: from tomorrow, within range.
    var isPlannable: Bool { self >= Self.earliest() && self <= Self.latest() }

    static func < (a: PlanDay, b: PlanDay) -> Bool { a.iso < b.iso }

    /// Midday on the day, in this phone's calendar. Midday rather than midnight
    /// so that no daylight-saving change can move it onto a neighbouring day.
    var date: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components) ?? .now
    }

    /// 1 is Sunday, 7 is Saturday, as `Calendar` counts them.
    var weekday: Int { Calendar.current.component(.weekday, from: date) }

    /// "Saturday".
    var weekdayName: String { date.formatted(.dateTime.weekday(.wide)) }

    /// "Sat", over "10", on the planner's row of days.
    var shortWeekday: String { date.formatted(.dateTime.weekday(.abbreviated)) }
    var dayNumber: String { date.formatted(.dateTime.day()) }

    /// "Saturday, October 10", in whatever order this phone writes dates.
    var long: String { date.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
}

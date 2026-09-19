import Foundation

/// The day somebody was born, and the only thing Arch derives an age from.
///
/// **Age used to be typed, and a typed age is a number that stops being true.**
/// It was a text field: whatever somebody wrote was stored as a birthdate
/// computed backwards from the day they wrote it, so "29" meant "born on this
/// date, twenty-nine years ago" — accurate for a day and wrong for the rest of
/// their life, drifting a year every birthday. Worse, `saveDetails` recomputed it
/// from the displayed age on *every* save, so editing your job title moved your
/// birthday. A date does not drift.
///
/// It is also the only honest way to ask the question the App Store requires an
/// answer to. "Are you eighteen" is a yes/no anybody can answer; a date is a
/// date, and the reader can correct a typo without anything being held against
/// them.
struct Birthday: Hashable, Codable {
    let year: Int
    let month: Int
    let day: Int

    /// Gregorian, and not `.current`, so the arithmetic does not change with the
    /// reader's locale. The timezone stays theirs: whether it is your birthday is
    /// a question about where you are.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Eighteen, and the reason it is here rather than in a view is that two
    /// screens ask it.
    static let minimumAge = 18

    /// How far back the year list goes. A hundred years is longer than anybody
    /// has been both alive and on a dating app.
    static let oldestYear = 100

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    var date: Date? { Self.calendar.date(from: components) }

    /// `yyyy-MM-dd`, which is what the `date` column takes.
    ///
    /// Built by hand rather than by `DateFormatter`, because a formatter carries
    /// a locale and a calendar and this has to be the same nine characters
    /// everywhere. A Buddhist or Japanese calendar locale would otherwise write
    /// a year the database reads as a different one.
    var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...Self.days(inYear: year, month: month)).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Whole years, counting the month and the day — so somebody whose birthday
    /// is tomorrow is still the age they were yesterday.
    func age(on now: Date = Date()) -> Int {
        guard let date, date <= now else { return 0 }
        return Self.calendar.dateComponents([.year], from: date, to: now).year ?? 0
    }

    func isOldEnough(on now: Date = Date()) -> Bool {
        age(on: now) >= Self.minimumAge
    }

    // MARK: The lists the picker offers

    /// Newest first: the years somebody signing up is most likely to pick are the
    /// ones nearest the top, and scrolling a hundred rows to reach 1998 is not a
    /// date picker, it is a penalty.
    static func years(now: Date = Date()) -> [Int] {
        let thisYear = calendar.component(.year, from: now)
        return Array(((thisYear - oldestYear)...thisYear).reversed())
    }

    /// From `DateFormatter` rather than written out, so "February" is spelled
    /// the way Foundation spells it and the list cannot drift from the index
    /// arithmetic that reads it.
    static let months: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.monthSymbols
            ?? ["January", "February", "March", "April", "May", "June", "July",
                "August", "September", "October", "November", "December"]
    }()

    /// **Thirty days hath September, and the picker has to know it.** February in
    /// a leap year is the case that makes this worth asking `Calendar` rather
    /// than writing a table: 2024 has 29, 1900 did not.
    static func days(inYear year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard (1...12).contains(month),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 31 }
        return range.count
    }

    /// How it reads back on the screen that collected it.
    var written: String {
        let name = (1...12).contains(month) ? Self.months[month - 1] : "—"
        return "\(day) \(name) \(year)"
    }
}

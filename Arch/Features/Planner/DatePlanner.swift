import Foundation

/// What a date can be about.
///
/// Interests in Arch are written, not picked from a list -- "Darkroom printing",
/// "Walking at night", "Brutalist car parks" -- so two people almost never share
/// one word for word. Matching the words would find nothing. Matching what the
/// words are *about* finds a lot: somebody who likes bridge inspections and
/// somebody who likes above-ground platforms both like how cities are built.
///
/// Seven themes, deliberately broad. A narrower set would split people who would
/// enjoy the same afternoon; a broader one would stop saying anything.
enum DateTheme: String, CaseIterable, Hashable, Identifiable {
    case outdoors, buildings, craft, food, words, sound, night

    var id: String { rawValue }

    /// The chip under "What you share".
    var label: String {
        switch self {
        case .outdoors:  return "Being outside"
        case .buildings: return "Buildings"
        case .craft:     return "Making things"
        case .food:      return "Food"
        case .words:     return "Words"
        case .sound:     return "Sound"
        case .night:     return "Late hours"
        }
    }

    /// The end of "You both like ___."
    var phrase: String {
        switch self {
        case .outdoors:  return "being outside"
        case .buildings: return "how cities are built"
        case .craft:     return "things made by hand"
        case .food:      return "good food"
        case .words:     return "books and language"
        case .sound:     return "how things sound"
        case .night:     return "the late hours"
        }
    }

    /// Lower-case fragments that point here. A fragment matches the *start* of a
    /// word -- "walk" finds "walking" and "walks" -- and one with a space in it
    /// matches the phrase anywhere. Starts of words rather than anywhere at all,
    /// because "late" is inside "articulated", and an interest in buses is not an
    /// interest in staying up. An interest can point at more than one theme:
    /// "Walking at night" is both outdoors and night, which is right.
    private var fragments: [String] {
        switch self {
        case .outdoors:
            return ["walk", "park", "tree", "dawn", "garden", "outdoor", "hike", "hiking",
                    "river", "beach", "swim", "climb", "cycl", "bike", "bird"]
        case .buildings:
            return ["bridge", "brutalis", "car park", "platform", "bus", "train", "subway",
                    "drainage", "architect", "street", "tower", "building", "transit"]
        case .craft:
            return ["darkroom", "rolleiflex", "camera", "photo", "print", "paper", "repair",
                    "pottery", "ceramic", "knit", "sew", "woodwork", "spines", "felt", "film"]
        case .food:
            return ["bak", "bread", "dulce", "cook", "food", "coffee", "dumpling", "market",
                    "noodle", "pastry", "wine", "tea", "cheese", "taco", "pizza"]
        case .words:
            return ["poet", "tense", "book", "read", "manual", "spines", "novel", "language",
                    "translat", "writing", "library", "essay"]
        case .sound:
            return ["sound", "room tone", "click track", "music", "jazz", "vinyl", "record",
                    "hammer", "piano", "noise", "engine", "choir", "concert", "synth"]
        case .night:
            return ["night", "four in the morning", "late", "laundromat", "midnight", "insomnia"]
        }
    }

    /// Every theme a piece of writing points at.
    static func themes(in text: String) -> Set<DateTheme> {
        let lowered = text.lowercased()
        let words = lowered.split { !$0.isLetter }.map(String.init)
        return Set(allCases.filter { theme in
            theme.fragments.contains { fragment in
                fragment.contains(" ")
                    ? lowered.contains(fragment)
                    : words.contains { $0.hasPrefix(fragment) }
            }
        })
    }

    /// Every theme a person's interests point at, and which interest pointed at
    /// each -- so a reason can quote the person's own words back.
    static func themes(of person: Person) -> [DateTheme: String] {
        var found: [DateTheme: String] = [:]
        for interest in person.interests {
            for theme in themes(in: interest.text) where found[theme] == nil {
                found[theme] = interest.text
            }
        }
        return found
    }
}

/// Somewhere to go.
struct Venue: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case coffee, walk, park, museum, library, studio, listening, food, bar, shop

        var label: String {
            switch self {
            case .coffee:    return "Coffee"
            case .walk:      return "A walk"
            case .park:      return "Park"
            case .museum:    return "Museum"
            case .library:   return "Library"
            case .studio:    return "Open studio"
            case .listening: return "Listening bar"
            case .food:      return "Something to eat"
            case .bar:       return "Drinks"
            case .shop:      return "Shop"
            }
        }

        /// A park and a walk are the same kind of afternoon.
        var isOutside: Bool { self == .walk || self == .park }

        /// How long a stop like this usually takes, in minutes. A guess the
        /// itinerary can be read against, not a booking.
        var minutes: Int {
            switch self {
            case .coffee:    return 45
            case .walk:      return 60
            case .park:      return 60
            case .museum:    return 90
            case .library:   return 60
            case .studio:    return 75
            case .listening: return 90
            case .food:      return 75
            case .bar:       return 60
            case .shop:      return 40
            }
        }
    }

    let id: String
    let name: String
    let kind: Kind
    let neighbourhood: String
    let coordinate: Coordinate
    let themes: Set<DateTheme>
    let times: Set<DatePlan.TimeOfDay>
    let roles: Set<DatePlan.Role>
}

/// A plan for one date.
struct DatePlan: Hashable {

    enum TimeOfDay: String, CaseIterable, Hashable, Identifiable {
        case afternoon, evening

        var id: String { rawValue }
        var title: String { self == .afternoon ? "Afternoon" : "Evening" }

        /// When the first stop starts, in minutes after midnight.
        var start: Int { self == .afternoon ? 14 * 60 : 18 * 60 + 30 }
    }

    /// What a stop is for. Three, because a first date that is one thing is an
    /// interview and a first date that is five things is a commute.
    enum Role: Int, CaseIterable, Hashable {
        case opener, main, closer

        var title: String {
            switch self {
            case .opener: return "To start"
            case .main:   return "The main thing"
            case .closer: return "To finish"
            }
        }
    }

    /// Getting from one stop to the next.
    struct Travel: Hashable {
        let minutes: Int
        let onFoot: Bool

        var label: String {
            onFoot ? "\(minutes) min walk" : "About \(minutes) min by transit"
        }
    }

    struct Stop: Identifiable, Hashable {
        let role: Role
        let venue: Venue
        /// Minutes after midnight.
        let start: Int
        /// How you get here from the stop before. Nil for the first.
        let travel: Travel?
        /// Why this one, in a sentence.
        let reason: String

        var id: String { "\(role.rawValue)-\(venue.id)" }
        var end: Int { start + venue.kind.minutes }
    }

    let time: TimeOfDay
    /// What both of you are into.
    let shared: [DateTheme]
    /// Interests written the same way by both of you. Rare, and worth saying
    /// when it happens.
    let sameWords: [String]
    /// The neighbourhood nearest the point halfway between you.
    let halfway: String?
    /// How far the first stop is from you, in kilometres.
    let fromYou: Double?
    /// How the first stop sits between the two of you, in words. Never a
    /// distance: Arch does not tell you how far away somebody lives.
    let fairness: String?
    let stops: [Stop]

    var endsAt: Int { stops.last?.end ?? time.start }
}

/// Builds a plan for two people from somewhere to go.
///
/// **The main thing anchors the date.** It is chosen first, for what you share
/// and for being about halfway; the stop before it and the stop after are then
/// chosen for being near it. Choosing the three in order instead -- best first
/// stop, then best second near that, and so on -- was tried first, and a good
/// first stop on the wrong side of the borough stranded the rest an hour away.
///
/// Ranked rather than optimised, so a swap is predictable: swapping the first or
/// last stop changes that stop and nothing else, and swapping the main thing
/// moves the date to wherever the next-best main thing is.
///
/// What a place scores for:
/// - something you both like, worth three;
/// - something only one of you likes, worth one;
/// - for the main thing, being near halfway and about as far for both of you;
/// - for the others, being near the main thing, and not being a second walk.
enum DatePlanner {

    /// Walking pace, and how much longer a real route is than a straight line.
    private static let kmPerHour = 4.8
    private static let detour = 1.25
    /// Past this many minutes on foot, a leg is offered as transit instead.
    private static let longestWalk = 25

    /// `skips` says, per role, how many times its stop has been swapped: the
    /// stop is the next-best place along the ranking, wrapping round.
    static func plan(
        you: Person,
        them: Person,
        time: DatePlan.TimeOfDay,
        venues: [Venue],
        skips: [DatePlan.Role: Int] = [:]
    ) -> DatePlan {
        let yours = DateTheme.themes(of: you)
        let theirs = DateTheme.themes(of: them)
        let shared = Set(yours.keys).intersection(theirs.keys)
        let oneSided = Set(yours.keys).symmetricDifference(theirs.keys)

        let sameWords = Set(you.interests.map { normalised($0.text) })
            .intersection(them.interests.map { normalised($0.text) })
        let sameWordsShown = them.interests.map(\.text).filter { sameWords.contains(normalised($0)) }

        // Theirs is the neighbourhood's centre and never anything finer. A
        // planner that used a more exact position than the profile shows would
        // be the one screen that could tell you where somebody lives.
        let yourPoint = you.matchPoint
        let theirPoint = them.place?.centre
        let middle: Coordinate? = {
            switch (yourPoint, theirPoint) {
            case let (a?, b?):
                return Coordinate(latitude: (a.latitude + b.latitude) / 2,
                                  longitude: (a.longitude + b.longitude) / 2)
            case let (a?, nil): return a
            case let (nil, b?): return b
            default:            return nil
            }
        }()

        func liking(_ venue: Venue) -> Double {
            3.0 * Double(venue.themes.intersection(shared).count)
                + 1.0 * Double(venue.themes.intersection(oneSided).count)
        }

        /// Near halfway, and about as far for one of you as for the other.
        func between(_ venue: Venue) -> Double {
            var cost = 0.0
            if let middle { cost += 0.8 * km(middle, venue.coordinate) }
            if let yourPoint, let theirPoint {
                cost += 0.5 * abs(km(yourPoint, venue.coordinate) - km(theirPoint, venue.coordinate))
            }
            return cost
        }

        func candidates(_ role: DatePlan.Role, besides used: Set<String>) -> [Venue] {
            venues.filter { $0.roles.contains(role) && $0.times.contains(time) && !used.contains($0.id) }
        }

        func pick(_ role: DatePlan.Role, from pool: [Venue], by score: (Venue) -> Double) -> Venue? {
            let ranked = pool.sorted {
                let a = score($0), b = score($1)
                return a == b ? $0.id < $1.id : a > b
            }
            guard !ranked.isEmpty else { return nil }
            return ranked[(skips[role] ?? 0) % ranked.count]
        }

        // The anchor.
        let main = pick(.main, from: candidates(.main, besides: [])) { liking($0) - between($0) }

        /// For the stops either side: near the main thing. With no main thing,
        /// halfway stands in for it.
        func nearMain(_ venue: Venue) -> Double {
            guard let main else { return liking(venue) - between(venue) }
            return liking(venue) - 1.5 * km(main.coordinate, venue.coordinate)
        }

        /// Not a second walk next to a walk. A rule rather than a penalty: as a
        /// penalty it lost to a park that two people both liked, and the plan
        /// became one long walk with a name change halfway. It gives way only if
        /// there is nothing else at all.
        func besideMain(_ pool: [Venue]) -> [Venue] {
            guard let main, main.kind.isOutside else { return pool }
            let indoors = pool.filter { !$0.kind.isOutside }
            return indoors.isEmpty ? pool : indoors
        }

        var used = Set(main.map { [$0.id] } ?? [])
        let opener = pick(.opener, from: besideMain(candidates(.opener, besides: used)), by: nearMain)
        if let opener { used.insert(opener.id) }
        let closer = pick(.closer, from: besideMain(candidates(.closer, besides: used)), by: nearMain)

        var stops: [DatePlan.Stop] = []
        var clock = time.start
        var previous: Venue?
        for (role, chosen) in [(DatePlan.Role.opener, opener), (.main, main), (.closer, closer)] {
            guard let venue = chosen else { continue }
            let leg = previous.map { travel(km($0.coordinate, venue.coordinate)) }
            // Rounded up to the next five minutes. "3:33" reads as computed; a
            // plan two people make reads "3:35".
            clock = ((clock + (leg?.minutes ?? 0) + 4) / 5) * 5
            stops.append(DatePlan.Stop(
                role: role,
                venue: venue,
                start: clock,
                travel: leg,
                reason: reason(for: venue, near: role == .main ? nil : main,
                               shared: shared, you: you, yours: yours,
                               them: them, theirs: theirs)
            ))
            clock += venue.kind.minutes
            previous = venue
        }

        let first = stops.first?.venue
        let fromYou = first.flatMap { venue in yourPoint.map { km($0, venue.coordinate) } }
        let fairness: String? = {
            guard let venue = first, let yourPoint, let theirPoint else { return nil }
            let difference = km(theirPoint, venue.coordinate) - km(yourPoint, venue.coordinate)
            if abs(difference) < 1 { return "About as far for \(them.name) as for you." }
            return difference > 0
                ? "A little further for \(them.name) than for you."
                : "A little further for you than for \(them.name)."
        }()

        return DatePlan(
            time: time,
            shared: DateTheme.allCases.filter { shared.contains($0) },
            sameWords: sameWordsShown,
            halfway: middle.flatMap(nearestNeighbourhood),
            fromYou: fromYou,
            fairness: fairness,
            stops: stops
        )
    }

    /// The message a plan becomes when you send it.
    static func message(for plan: DatePlan) -> String {
        let lines = plan.stops.map { "\(clockTime($0.start)) · \($0.venue.name), \($0.venue.neighbourhood)" }
        return (["How about this?"] + lines).joined(separator: "\n")
    }

    /// "2:00 pm". Written by hand rather than through a `DateFormatter`, because
    /// a plan is a time of day with no date attached, and a formatter wants one.
    static func clockTime(_ minutes: Int) -> String {
        let hour = (minutes / 60) % 24, minute = minutes % 60
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", twelve, minute, hour < 12 ? "am" : "pm")
    }

    // MARK: Pieces

    private static func reason(
        for venue: Venue,
        near anchor: Venue?,
        shared: Set<DateTheme>,
        you: Person, yours: [DateTheme: String],
        them: Person, theirs: [DateTheme: String]
    ) -> String {
        let order = DateTheme.allCases
        if let theme = order.first(where: { venue.themes.contains($0) && shared.contains($0) }) {
            return "You both like \(theme.phrase)."
        }
        if let theme = order.first(where: { venue.themes.contains($0) && theirs[$0] != nil }),
           let words = theirs[theme] {
            return "\(them.name) wrote \u{201C}\(words)\u{201D}."
        }
        if let theme = order.first(where: { venue.themes.contains($0) && yours[$0] != nil }),
           let words = yours[theme] {
            return "You wrote \u{201C}\(words)\u{201D}."
        }
        // Nothing either of you wrote points here, so say what did choose it:
        // being near the main thing, or, for the main thing itself, the middle.
        // "Close" only when it is: a walk, not a ride.
        if let anchor, anchor.id != venue.id {
            return travel(km(anchor.coordinate, venue.coordinate)).onFoot
                ? "A short walk from \(anchor.name)."
                : "The closest option to \(anchor.name)."
        }
        return "About halfway between you."
    }

    private static func normalised(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// On foot if it is a walk two people would take; otherwise a rough transit
    /// time -- a ride at city speed plus ten minutes of waiting and walking to it,
    /// rounded up to five, because it is an estimate and should look like one.
    private static func travel(_ km: Double) -> DatePlan.Travel {
        let walking = km * detour / kmPerHour * 60
        if walking <= Double(longestWalk) {
            return DatePlan.Travel(minutes: max(1, Int(walking.rounded())), onFoot: true)
        }
        let riding = km * detour / 20 * 60 + 10
        return DatePlan.Travel(minutes: Int((riding / 5).rounded(.up)) * 5, onFoot: false)
    }

    private static func nearestNeighbourhood(to point: Coordinate) -> String? {
        PlaceLibrary.all
            .compactMap { place in place.centre.map { (place.name, km(point, $0)) } }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Great-circle distance. Exact enough at city scale, and needs nothing
    /// from MapKit.
    static func km(_ a: Coordinate, _ b: Coordinate) -> Double {
        let radius = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }
}

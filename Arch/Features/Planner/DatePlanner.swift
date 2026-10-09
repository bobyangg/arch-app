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
        case coffee, walk, park, museum, library, studio, listening, show, food, bar, shop

        var label: String {
            switch self {
            case .coffee:    return "Coffee"
            case .walk:      return "A walk"
            case .park:      return "Park"
            case .museum:    return "Museum"
            case .library:   return "Library"
            case .studio:    return "Open studio"
            case .listening: return "Listening bar"
            case .show:      return "Something live"
            case .food:      return "Something to eat"
            case .bar:       return "Drinks"
            case .shop:      return "Shop"
            }
        }

        /// A park and a walk are the same kind of afternoon.
        var isOutside: Bool { self == .walk || self == .park }

        /// The hours a place of this kind usually keeps, for a place whose own
        /// hours nobody has told the app -- every place from Apple Maps, which
        /// does not give apps opening hours (see `VenueSearch`). Deliberately
        /// the ordinary day: a café that opens late is rarer than one that
        /// closes at six.
        var typicalHours: OpeningHours {
            switch self {
            case .coffee:    return OpeningHours(opens: 7 * 60, closes: 18 * 60)
            case .walk:      return OpeningHours(opens: 6 * 60, closes: 23 * 60)
            case .park:      return OpeningHours(opens: 6 * 60, closes: 22 * 60)
            case .museum:    return OpeningHours(opens: 10 * 60, closes: 17 * 60 + 30)
            case .library:   return OpeningHours(opens: 10 * 60, closes: 18 * 60)
            case .studio:    return OpeningHours(opens: 11 * 60, closes: 19 * 60)
            case .listening: return OpeningHours(opens: 17 * 60, closes: 25 * 60)
            case .show:      return OpeningHours(opens: 18 * 60, closes: 23 * 60 + 30)
            case .food:      return OpeningHours(opens: 11 * 60 + 30, closes: 22 * 60 + 30)
            case .bar:       return OpeningHours(opens: 16 * 60, closes: 26 * 60)
            case .shop:      return OpeningHours(opens: 10 * 60, closes: 20 * 60)
            }
        }

        /// Which button adds it: something to eat or drink, or something to do.
        var category: DatePlan.Category {
            switch self {
            case .coffee, .food, .bar: return .food
            default:                   return .activity
            }
        }

        /// A place you go *for* a drink. Somewhere live that also has a bar is
        /// not, which is why a performance is its own kind rather than a
        /// listening bar: "I don't drink" should take away the bars and leave
        /// the concert.
        var isDrinkLed: Bool { self == .bar || self == .listening }

        /// Roughly what it costs two people: nothing, a little, or a meal's
        /// worth. Read against the lower of two budgets, never shown as a price.
        var price: Int {
            switch self {
            case .walk, .park, .library, .shop:  return 0
            case .coffee, .museum, .studio:      return 1
            case .listening, .show, .food, .bar: return 2
            }
        }

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
            case .show:      return 90
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
    /// Days of the week it is shut, as `Calendar` numbers them: 1 is Sunday.
    var closedOn: Set<Int> = []
    /// Its own opening hours, when they are known. Nil means nobody has said,
    /// and the hours its kind usually keeps stand in -- see `openingHours`.
    var hours: OpeningHours? = nil

    /// What the planner checks a stop against: its own hours, or its kind's.
    var openingHours: OpeningHours { hours ?? kind.typicalHours.typical }

    func isOpen(on day: PlanDay?) -> Bool {
        guard let day else { return true }
        return !closedOn.contains(day.weekday)
    }
}

/// When a place is open, in minutes after midnight. A close after midnight is
/// written past it -- a bar open until two is `closes: 26 * 60` -- so that one
/// evening is one range and "open until" is a single comparison.
struct OpeningHours: Hashable {
    let opens: Int
    let closes: Int
    /// True for the hours a place of its kind usually keeps rather than its
    /// own. Said on the card ("Usually open"), so nobody mistakes a guess for
    /// a fact.
    var isTypical: Bool = false

    var typical: OpeningHours { OpeningHours(opens: opens, closes: closes, isTypical: true) }

    /// Open for the whole of a stop, from when you arrive to when you leave.
    func covers(from start: Int, to end: Int) -> Bool {
        start >= opens && end <= closes
    }

    /// "11:00 am – 6:00 pm".
    var label: String {
        "\(DatePlanner.clockTime(opens)) \u{2013} \(DatePlanner.clockTime(closes))"
    }
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

    /// What an item on the plan is. Two, because that is the choice two people
    /// actually make -- "get something to eat" or "do something" -- and the
    /// planner can find the particular place.
    enum Category: String, CaseIterable, Codable, Hashable, Identifiable {
        case food, activity

        var id: String { rawValue }
        var title: String { self == .food ? "Food & drink" : "Activity" }

        /// How long one usually runs, until it is changed.
        var defaultHours: Int { self == .food ? 1 : 2 }
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
        /// The item this fills: one stop per item you added and chose for.
        let itemID: UUID
        let category: Category
        let venue: Venue
        /// Minutes after midnight.
        let start: Int
        /// The block you gave it: one, two or three hours.
        let minutes: Int
        /// How you get here from the stop before. Nil for the first.
        let travel: Travel?
        /// Why this one, in a sentence, for the screen you are looking at:
        /// "You wrote 'Room tone'".
        let reason: String
        /// The same, for a message both of you will read: "Sam wrote 'Room
        /// tone'". Only "you" changes; everything else already reads the same
        /// from either side.
        let sharedReason: String
        /// Whether Swap has anywhere else to go. False when this is the only
        /// place that fits -- under "keep it walkable" and "I don't drink",
        /// near some anchors, that happens -- and then the screen offers no
        /// Swap rather than one that changes nothing.
        let canSwap: Bool
        /// The stop the rest of the date is built around.
        let isAnchor: Bool
        /// The stop this one was placed beside -- the next one in towards the
        /// anchor. Nil for the anchor itself.
        let placedNear: String?
        /// Whether the place is open for the whole stop, as the stop actually
        /// falls once the walks between are known. Places are chosen to be
        /// open with time to spare for getting there, so this is almost always
        /// true; when a long leg pushes a stop past closing, the card says so.
        let isOpenThroughout: Bool

        var id: UUID { itemID }
        var end: Int { start + minutes }
    }

    let time: TimeOfDay
    /// Which day. Nil only for a plan made without one.
    let day: PlanDay?
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

/// One thing on the plan, as you set it up: what kind of thing, how long, and
/// how many times it has been swapped. Which *place* it is, the planner works
/// out -- every time it is drawn, from both of you as you are now.
///
/// A plan opens with one blank item and holds at most three.
struct PlanItem: Identifiable, Hashable {
    let id: UUID
    /// Nil while blank: added, and not yet told what it is.
    var category: DatePlan.Category?
    /// One, two or three.
    var hours: Int
    /// How many times it has been swapped: the next-best place along its
    /// ranking, wrapping round.
    var skips: Int

    init(category: DatePlan.Category? = nil, hours: Int? = nil) {
        id = UUID()
        self.category = category
        self.hours = hours ?? category?.defaultHours ?? 1
        skips = 0
    }

    /// Three, because a first date that is one thing is an interview and one
    /// that is five things is a commute.
    static let maximum = 3
    static let hourChoices = [1, 2, 3]
}

/// Builds a plan for two people from the items they asked for.
///
/// **One stop anchors the date**: the first activity, or the first item if
/// there is no activity. It is chosen first, for what you share and for being
/// about halfway; every other stop is then chosen for being near it. Choosing
/// in order instead -- best first stop, then the best near that -- was tried
/// first, and a good first stop on the wrong side of the borough stranded the
/// rest an hour away.
///
/// Ranked rather than optimised, so a swap is predictable: swapping a stop
/// changes that stop and nothing else, except the anchor, which moves the date
/// to wherever the next-best anchor is.
///
/// What a place scores for:
/// - something you both like, worth three;
/// - something only one of you likes, worth one;
/// - for the anchor, being near halfway and about as far for both of you;
/// - for the others, being near the anchor, and not being a second walk;
/// - and, for every stop, how well it fits what you each said a date should be
///   (`DateFit`) -- with "I don't drink" and "keep it walkable" applied as
///   rules rather than weighed, whichever of you said them.
enum DatePlanner {

    /// Walking pace, and how much longer a real route is than a straight line.
    private static let kmPerHour = 4.8
    private static let detour = 1.25
    /// Past this many minutes on foot, a leg is offered as transit instead.
    private static let longestWalk = 25
    /// What the hours check allows for getting from one stop to the next,
    /// before the stops are known: a walk at its longest, and the rounding up
    /// to five minutes. A longer leg is rare, and the card says if it happens.
    private static let legAllowance = 30
    /// From when a stop counts as part of the evening.
    private static let eveningFrom = 17 * 60

    /// `items` are what you added, in order. A blank one is skipped; the rest
    /// each become a stop, if anywhere fits.
    ///
    /// `day` takes out anywhere shut that day. A plan that sent two people to
    /// a museum on the day it is closed would be the planner being wrong about
    /// the one thing it is for.
    ///
    /// `theirCentre` and `halfwayName` come from Apple Maps when the venues do
    /// (see `VenueSearch`): a profile from the server names a neighbourhood but
    /// carries no position, so its centre has to be looked up, and the halfway
    /// point has to be named by something that knows more than New York.
    static func plan(
        you: Person,
        them: Person,
        time: DatePlan.TimeOfDay,
        day: PlanDay? = nil,
        venues: [Venue],
        items: [PlanItem],
        theirCentre: Coordinate? = nil,
        halfwayName: String? = nil
    ) -> DatePlan {
        // What you each said a date should be like. Either may be missing:
        // somebody who has not answered is planned for from interests alone.
        let fit = DateFit(yours: you.datePreferences, theirs: them.datePreferences)

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
        let theirPoint = theirCentre ?? them.place?.centre
        let middle = Self.middle(yourPoint, theirPoint)

        func liking(_ venue: Venue) -> Double {
            3.0 * Double(venue.themes.intersection(shared).count)
                + 1.0 * Double(venue.themes.intersection(oneSided).count)
                + fit.score(venue)
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

        // The items that have been told what they are, in your order.
        let filled = items.filter { $0.category != nil }

        /// **When each item will happen, before any place is chosen.** The
        /// earliest it can start is the date's start plus every block before
        /// it; the latest it can end allows for getting between the stops.
        /// Checking the time of day alone -- "afternoon" -- was not enough
        /// once a date could run nine hours: a café that shuts at six could
        /// land at seven. A place has to be open across the whole window.
        let windows: [(start: Int, end: Int)] = {
            var start = time.start
            return filled.enumerated().map { index, item in
                defer { start += item.hours * 60 }
                return (start, start + index * Self.legAllowance + item.hours * 60)
            }
        }()

        func candidates(_ category: DatePlan.Category, at index: Int, besides used: Set<String>) -> [Venue] {
            let window = windows[index]
            // Afternoon or evening by when this item starts, not when the
            // date does: the third thing on a long afternoon is an evening
            // thing, and a bar should be able to be it.
            let part: DatePlan.TimeOfDay = window.start >= Self.eveningFrom ? .evening : .afternoon
            return venues.filter {
                $0.kind.category == category && $0.times.contains(part) && $0.isOpen(on: day)
                    && $0.openingHours.covers(from: window.start, to: window.end)
                    && !used.contains($0.id) && fit.allows($0)
            }
        }

        func pick(_ pool: [Venue], skips: Int, by score: (Venue) -> Double) -> Venue? {
            let ranked = pool.sorted {
                let a = score($0), b = score($1)
                return a == b ? $0.id < $1.id : a > b
            }
            guard !ranked.isEmpty else { return nil }
            return ranked[skips % ranked.count]
        }

        guard let anchorIndex = filled.firstIndex(where: { $0.category == .activity })
                ?? (filled.isEmpty ? nil : 0),
              let anchorCategory = filled[anchorIndex].category
        else {
            return DatePlan(time: time, day: day,
                            shared: DateTheme.allCases.filter { shared.contains($0) },
                            sameWords: sameWordsShown,
                            halfway: halfwayName ?? middle.flatMap(nearestNeighbourhood),
                            fromYou: nil, fairness: nil, stops: [])
        }

        /// "Keep it walkable" starts with the anchor: it has to be somewhere
        /// with enough of every other item you asked for on foot from it --
        /// and, for an anchor outdoors, indoors, or the only thing on foot from
        /// a park is the next park along. Choosing the anchor as usual and then
        /// looking for what was near it found, a quarter of the time, an anchor
        /// with nothing near it -- and a walkable date with a train in it.
        func hasCompany(_ anchor: Venue) -> Bool {
            // Per item, what could fill it on foot from the anchor -- open at
            // that item's time. Each needs one, and two of a kind need two.
            var byCategory: [DatePlan.Category: (items: Int, places: Set<String>)] = [:]
            for (index, item) in filled.enumerated() where index != anchorIndex {
                guard let category = item.category else { continue }
                let near = candidates(category, at: index, besides: [anchor.id]).filter {
                    travel(km(anchor.coordinate, $0.coordinate)).onFoot
                        && !(anchor.kind.isOutside && $0.kind.isOutside)
                }
                if near.isEmpty { return false }
                byCategory[category, default: (0, [])].items += 1
                byCategory[category, default: (0, [])].places.formUnion(near.map(\.id))
            }
            return byCategory.values.allSatisfy { $0.places.count >= $0.items }
        }

        let anchors = candidates(anchorCategory, at: anchorIndex, besides: [])
        let reachable = fit.walkable && filled.count > 1 ? anchors.filter(hasCompany) : anchors
        let anchorPool = reachable.isEmpty ? anchors : reachable
        let anchor = pick(anchorPool, skips: filled[anchorIndex].skips) { liking($0) - between($0) }

        /// Every other stop is placed beside one already placed: outward from
        /// the anchor, each near the stop on the anchor's side of it. Near the
        /// anchor alone was not enough -- two cafés either side of a park are
        /// each a walk from the park and not from each other, and with items in
        /// any order a walkable date had a train in it.
        func score(_ venue: Venue, near reference: Venue?) -> Double {
            guard let reference else { return liking(venue) - between(venue) }
            return liking(venue) - 1.5 * km(reference.coordinate, venue.coordinate)
        }

        /// "Keep it walkable": only what is a walk from that stop. It gives way
        /// only when nothing at all is in reach -- and then the leg says "by
        /// transit", so the plan never pretends.
        func inReach(_ pool: [Venue], of reference: Venue?) -> [Venue] {
            guard fit.walkable, let reference else { return pool }
            let near = pool.filter { travel(km(reference.coordinate, $0.coordinate)).onFoot }
            return near.isEmpty ? pool : near
        }

        var chosen: [Int: Venue] = [:]
        var placedNear: [Int: Venue] = [:]
        var poolSizes: [Int: Int] = [anchorIndex: anchorPool.count]
        if let anchor { chosen[anchorIndex] = anchor }

        /// Not a second walk next to a walk. A rule rather than a penalty: as a
        /// penalty it lost to a park that two people both liked, and the plan
        /// became one long walk with a name change halfway. It gives way only
        /// if there is nothing else at all.
        func notBesideAWalk(_ pool: [Venue], at index: Int) -> [Venue] {
            let neighbours = [index - 1, index + 1].compactMap { chosen[$0] }
            guard neighbours.contains(where: { $0.kind.isOutside }) else { return pool }
            let indoors = pool.filter { !$0.kind.isOutside }
            return indoors.isEmpty ? pool : indoors
        }

        let outward = filled.indices
            .filter { $0 != anchorIndex }
            .sorted { (abs($0 - anchorIndex), $0) < (abs($1 - anchorIndex), $1) }
        for index in outward {
            guard let category = filled[index].category else { continue }
            let reference = chosen[index < anchorIndex ? index + 1 : index - 1] ?? anchor
            placedNear[index] = reference
            let used = Set(chosen.values.map(\.id))
            let pool = notBesideAWalk(inReach(candidates(category, at: index, besides: used),
                                              of: reference),
                                      at: index)
            poolSizes[index] = pool.count
            if let venue = pick(pool, skips: filled[index].skips, by: { score($0, near: reference) }) {
                chosen[index] = venue
            }
        }

        var stops: [DatePlan.Stop] = []
        var clock = time.start
        var previous: Venue?
        for (index, item) in filled.enumerated() {
            guard let venue = chosen[index], let category = item.category else { continue }
            let leg = previous.map { travel(km($0.coordinate, venue.coordinate)) }
            // Rounded up to the next five minutes. "3:33" reads as computed; a
            // plan two people make reads "3:35".
            clock = ((clock + (leg?.minutes ?? 0) + 4) / 5) * 5
            let near = index == anchorIndex ? nil : placedNear[index]
            stops.append(DatePlan.Stop(
                itemID: item.id,
                category: category,
                venue: venue,
                start: clock,
                minutes: item.hours * 60,
                travel: leg,
                reason: reason(for: venue, near: near,
                               shared: shared, you: you, yours: yours,
                               them: them, theirs: theirs, yourName: "You"),
                sharedReason: reason(for: venue, near: near,
                                     shared: shared, you: you, yours: yours,
                                     them: them, theirs: theirs, yourName: you.name),
                canSwap: (poolSizes[index] ?? 0) > 1,
                isAnchor: index == anchorIndex,
                placedNear: near?.name,
                isOpenThroughout: venue.openingHours.covers(from: clock, to: clock + item.hours * 60)
            ))
            clock += item.hours * 60
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
            day: day,
            shared: DateTheme.allCases.filter { shared.contains($0) },
            sameWords: sameWordsShown,
            halfway: halfwayName ?? middle.flatMap(nearestNeighbourhood),
            fromYou: fromYou,
            fairness: fairness,
            stops: stops
        )
    }

    /// Halfway between two points, or whichever one there is.
    static func middle(_ a: Coordinate?, _ b: Coordinate?) -> Coordinate? {
        switch (a, b) {
        case let (a?, b?):
            return Coordinate(latitude: (a.latitude + b.latitude) / 2,
                              longitude: (a.longitude + b.longitude) / 2)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default:            return nil
        }
    }

    /// The message a plan becomes when you send it. The day goes in the first
    /// line, because the first line is what a notification shows.
    static func message(for plan: DatePlan) -> String {
        let lines = plan.stops.map { "\(clockTime($0.start)) · \($0.venue.name), \($0.venue.neighbourhood)" }
        let opening = plan.day.map { "How about \($0.long)?" } ?? "How about this?"
        return ([opening] + lines).joined(separator: "\n")
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
        them: Person, theirs: [DateTheme: String],
        yourName: String
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
            return "\(yourName) wrote \u{201C}\(words)\u{201D}."
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

    /// The nearest of the bundled neighbourhoods, if one is actually near.
    ///
    /// **Within five kilometres, or nothing.** The bundled list is New York, so
    /// without a limit a halfway point in Toronto was "About halfway: Bay Ridge",
    /// five hundred kilometres off. The real build names the point with Apple
    /// Maps instead and only falls back to this.
    private static func nearestNeighbourhood(to point: Coordinate) -> String? {
        PlaceLibrary.all
            .compactMap { place in place.centre.map { (place.name, km(point, $0)) } }
            .filter { $0.1 <= 5 }
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

import Foundation

/// What a date can be about.
///
/// Interests in Arch are written, not picked from a list -- "Darkroom printing",
/// "Walking at night", "Brutalist car parks" -- so two people almost never share
/// one word for word. Matching the words would find nothing. Matching what the
/// words are *about* finds a lot: somebody who likes bridge inspections and
/// somebody who likes above-ground platforms both like how cities are built.
///
/// Nine themes, deliberately broad. A narrower set would split people who would
/// enjoy the same afternoon; a broader one would stop saying anything.
///
/// **The words were the mock people's, and real people do not write like them.**
/// The first lists were built from "Darkroom printing" and "Brutalist car parks",
/// and the first two real profiles -- "Gaming", "Gym", "Cooking"; "wood
/// shopping", "arcade", "drinking" -- matched one theme between them, so the
/// planner planned for one person's cooking and nothing of the other's. The lists
/// now carry everyday words too, and `play` and `active` exist because games and
/// staying active are two of the commonest things anybody writes.
enum DateTheme: String, CaseIterable, Hashable, Identifiable {
    case outdoors, buildings, craft, food, words, sound, night, play, active

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
        case .play:      return "Games"
        case .active:    return "Staying active"
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
        case .play:      return "playing games"
        case .active:    return "staying active"
        }
    }

    /// Lower-case fragments that point here. A fragment matches the *start* of a
    /// word -- "walk" finds "walking" and "walks" -- and one with a space in it
    /// matches the phrase anywhere. Starts of words rather than anywhere at all,
    /// because "late" is inside "articulated", and an interest in buses is not an
    /// interest in staying up. An interest can point at more than one theme:
    /// "Walking at night" is both outdoors and night, which is right.
    ///
    /// A fragment starting with `=` matches only the whole word, for the short
    /// ones whose starts are everywhere: "=bar" is a bar and not a barber or a
    /// barbecue, "=tea" is tea and not teaching, "=run" is running and not a
    /// runway.
    private var fragments: [String] {
        switch self {
        case .outdoors:
            return ["walk", "park", "tree", "dawn", "garden", "outdoor", "hike", "hiking",
                    "river", "beach", "swim", "climb", "cycl", "bike", "bird",
                    "camp", "fishing", "kayak", "canoe", "sail", "lake", "mountain", "nature",
                    "picnic", "trail", "ocean", "=sea", "snow", "stargaz", "dog", "sunset",
                    "sunrise", "island", "boat"]
        case .buildings:
            return ["bridge", "brutalis", "car park", "platform", "bus", "train", "subway",
                    "drainage", "architect", "street", "tower", "building", "transit",
                    "city", "urban", "skyline", "interior", "history", "historic", "museum"]
        case .craft:
            return ["darkroom", "rolleiflex", "camera", "photo", "print", "paper", "repair",
                    "pottery", "ceramic", "knit", "sew", "woodwork", "spines", "felt", "film",
                    "wood", "diy", "paint", "draw", "sketch", "=art", "=arts", "artist", "artwork",
                    "sculpt", "crochet", "embroider", "quilt", "carpent", "craft", "maker",
                    "candle", "jewel", "leather", "design", "illustrat", "lego"]
        case .food:
            return ["bak", "bread", "dulce", "cook", "food", "coffee", "dumpling", "market",
                    "noodle", "pastry", "wine", "=tea", "cheese", "taco", "pizza",
                    "=eat", "eating", "restaurant", "brunch", "sushi", "ramen", "bbq",
                    "barbecue", "grill", "chef", "foodie", "dessert", "ice cream", "chocolate",
                    "curry", "dim sum", "boba", "matcha", "latte", "espresso", "dining",
                    "cuisine", "recipe", "kitchen", "burger", "pho", "spicy", "cafe", "café"]
        case .words:
            return ["poet", "tense", "book", "read", "manual", "spines", "novel", "language",
                    "translat", "writing", "library", "essay",
                    "writer", "journal", "comic", "manga", "literat", "philosoph", "podcast",
                    "debate", "story", "stories", "learn"]
        case .sound:
            return ["sound", "room tone", "click track", "music", "jazz", "vinyl", "record",
                    "hammer", "piano", "noise", "engine", "choir", "concert", "synth",
                    "singing", "singer", "guitar", "drum", "=band", "=bands", "=dj", "song", "opera",
                    "orchestra", "violin", "=rap", "hip hop", "festival", "=gig", "=gigs",
                    "karaoke", "spotify"]
        case .night:
            return ["night", "four in the morning", "late", "laundromat", "midnight", "insomnia",
                    "drink", "=bar", "=bars", "bar hopping", "=pub", "=pubs", "cocktail", "beer",
                    "brew", "whisk", "=club", "clubs", "clubbing", "party", "partying",
                    "danc", "rave", "karaoke", "comedy", "stand up", "stand-up"]
        case .play:
            return ["gam", "arcade", "board game", "video game", "puzzle", "trivia", "bowling",
                    "billiard", "=pool", "dart", "chess", "poker", "escape room", "mini golf",
                    "minigolf", "pinball", "nintendo", "playstation", "xbox", "=cards",
                    "card game", "go kart", "karting", "lego"]
        case .active:
            return ["=gym", "fitness", "workout", "working out", "lifting", "weightlift",
                    "=weights", "=run", "running", "runner", "jog", "marathon", "yoga",
                    "pilates", "sport", "basketball", "soccer", "football", "tennis",
                    "volleyball", "badminton", "hockey", "skat", "skiing", "snowboard",
                    "surf", "boxing", "martial", "climb", "bouldering", "golf", "crossfit",
                    "cycl", "swim", "hike", "hiking"]
        }
    }

    /// Every theme a piece of writing points at.
    static func themes(in text: String) -> Set<DateTheme> {
        let lowered = text.lowercased()
        let words = lowered.split { !$0.isLetter }.map(String.init)
        return Set(allCases.filter { theme in
            theme.fragments.contains { fragment in
                if fragment.hasPrefix("=") {
                    return words.contains(String(fragment.dropFirst()))
                }
                return fragment.contains(" ") || fragment.contains("-")
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
        /// An arcade, bowling, mini golf, a board-game café, a climbing gym:
        /// somewhere you go to *do* something together. Only from Apple Maps.
        case activity

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
            case .activity:  return "Something to do"
            }
        }

        /// A park and a walk are the same kind of afternoon.
        var isOutside: Bool { self == .walk || self == .park }

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
            case .coffee, .museum, .studio, .activity: return 1
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
            case .activity:  return 75
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
    /// Days of the week it is shut, as `Calendar` numbers them: 1 is Sunday.
    var closedOn: Set<Int> = []

    func isOpen(on day: PlanDay?) -> Bool {
        guard let day else { return true }
        return !closedOn.contains(day.weekday)
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
        /// Why this one, in a sentence, for the screen you are looking at:
        /// "You wrote 'Room tone'".
        let reason: String
        /// The same, for a message both of you will read: "Sam wrote 'Room
        /// tone'". Only "you" changes; everything else already reads the same
        /// from either side.
        let sharedReason: String
        /// Whether Swap has anywhere else to go. False when this is the only
        /// place that can play this part -- under "keep it walkable" and "I
        /// don't drink", next to some main things, that is often -- and then
        /// the screen offers no Swap rather than one that changes nothing.
        let canSwap: Bool

        var id: String { "\(role.rawValue)-\(venue.id)" }
        var end: Int { start + venue.kind.minutes }
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
/// - for the others, being near the main thing, and not being a second walk;
/// - and, for every stop, how well it fits what you each said a date should be
///   (`DateFit`) -- with "I don't drink" and "keep it walkable" applied as
///   rules rather than weighed, whichever of you said them.
enum DatePlanner {

    /// Walking pace, and how much longer a real route is than a straight line.
    private static let kmPerHour = 4.8
    private static let detour = 1.25
    /// Past this many minutes on foot, a leg is offered as transit instead.
    private static let longestWalk = 25

    /// `skips` says, per role, how many times its stop has been swapped: the
    /// stop is the next-best place along the ranking, wrapping round.
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
        skips: [DatePlan.Role: Int] = [:],
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

        func candidates(_ role: DatePlan.Role, besides used: Set<String>) -> [Venue] {
            venues.filter {
                $0.roles.contains(role) && $0.times.contains(time) && $0.isOpen(on: day)
                    && !used.contains($0.id) && fit.allows($0)
            }
        }

        func pick(_ role: DatePlan.Role, from pool: [Venue], by score: (Venue) -> Double) -> Venue? {
            let ranked = pool.sorted {
                let a = score($0), b = score($1)
                return a == b ? $0.id < $1.id : a > b
            }
            guard !ranked.isEmpty else { return nil }
            return ranked[(skips[role] ?? 0) % ranked.count]
        }

        /// What could stand either side of a main thing, on foot from it -- and
        /// not a second walk beside a walk.
        func onFoot(from main: Venue, _ role: DatePlan.Role) -> [Venue] {
            candidates(role, besides: [main.id]).filter {
                travel(km(main.coordinate, $0.coordinate)).onFoot
                    && !(main.kind.isOutside && $0.kind.isOutside)
            }
        }

        /// "Keep it walkable" starts with the main thing: it has to be somewhere
        /// with a first and a last stop on foot from it. Choosing the main thing
        /// as usual and then looking for what was near it found, a quarter of
        /// the time, a main thing with nothing near it at all -- and a walkable
        /// date with a train in it.
        func hasCompany(_ main: Venue) -> Bool {
            let openers = onFoot(from: main, .opener), closers = onFoot(from: main, .closer)
            guard let opener = openers.first, let closer = closers.first else { return false }
            return openers.count > 1 || closers.count > 1 || opener.id != closer.id
        }

        // The anchor.
        let mains = candidates(.main, besides: [])
        let reachable = fit.walkable ? mains.filter(hasCompany) : mains
        let mainPool = reachable.isEmpty ? mains : reachable
        let main = pick(.main, from: mainPool) { liking($0) - between($0) }

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

        /// "Keep it walkable": only what is a walk from the main thing. Like
        /// `besideMain`, it gives way only when nothing at all is in reach --
        /// and then the leg says "by transit", so the plan never pretends.
        func inReach(_ pool: [Venue]) -> [Venue] {
            guard fit.walkable, let main else { return pool }
            let near = pool.filter { travel(km(main.coordinate, $0.coordinate)).onFoot }
            return near.isEmpty ? pool : near
        }

        var used = Set(main.map { [$0.id] } ?? [])
        let openerPool = besideMain(inReach(candidates(.opener, besides: used)))
        let opener = pick(.opener, from: openerPool, by: nearMain)
        if let opener { used.insert(opener.id) }
        let closerPool = besideMain(inReach(candidates(.closer, besides: used)))
        let closer = pick(.closer, from: closerPool, by: nearMain)
        let choices: [DatePlan.Role: Int] = [.opener: openerPool.count, .main: mainPool.count,
                                             .closer: closerPool.count]

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
                               them: them, theirs: theirs, yourName: "You"),
                sharedReason: reason(for: venue, near: role == .main ? nil : main,
                                     shared: shared, you: you, yours: yours,
                                     them: them, theirs: theirs, yourName: you.name),
                canSwap: (choices[role] ?? 0) > 1
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

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
        /// Bowling, mini golf, climbing, skating: something you do together
        /// rather than look at.
        case play
        /// A film.
        case cinema
        /// An aquarium, a zoo, a planetarium, an amusement park.
        case attraction

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
            case .play:       return "Something to play"
            case .cinema:     return "A film"
            case .attraction: return "A day out"
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
            case .play:       return OpeningHours(opens: 11 * 60, closes: 23 * 60)
            case .cinema:     return OpeningHours(opens: 12 * 60, closes: 24 * 60)
            case .attraction: return OpeningHours(opens: 10 * 60, closes: 18 * 60)
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
            case .walk, .park, .library, .shop:          return 0
            case .coffee, .museum, .studio, .play, .cinema: return 1
            case .listening, .show, .food, .bar, .attraction: return 2
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
            case .play:       return 90
            case .cinema:     return 120
            case .attraction: return 120
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

    /// Apple Maps' own identifier for this place, from iOS 18. The Maps
    /// button opens exactly this place with it (`VenueSearch.openInMaps`).
    var mapsID: String? = nil

    /// How near the top of Apple's answer it came, 1 for first and towards 0
    /// for last. Apple puts the places people actually go to first, and this is
    /// the nearest thing to a review count MapKit gives an app.
    var prominence: Double = 0

    /// This place in Apple Maps, as a pin at its own coordinates with its name
    /// on it -- for an iPhone without `mapsID`.
    ///
    /// **This used to search for the name near the place, and that was wrong
    /// twice.** "Outdoor" landed on whichever of six places called something
    /// Outdoor Apple liked best; "Lake Devo", which Apple's search could not
    /// find by name, landed on the address at that spot -- a street corner.
    /// The name is now only the pin's label; the coordinates say where.
    var mapsURL: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f",
                                                    coordinate.latitude, coordinate.longitude)),
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "z", value: "17"),
        ]
        return parts?.url
    }

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
    /// A particular place, kept as it is rather than chosen: what "Change it"
    /// on a plan in a thread fills the planner with, so the plan on screen is
    /// the plan that was sent -- the same places, not ones like them. Swapping
    /// it lets the planner choose again.
    var pinned: Venue?
    /// Where a kept place came from, said under it: "From Hana's plan."
    var pinnedFrom: String?
    /// Places swapped away from a kept one, so a swap moves on rather than
    /// landing on the place it just left.
    var passed: Set<String>

    init(category: DatePlan.Category? = nil, hours: Int? = nil,
         pinned: Venue? = nil, pinnedFrom: String? = nil) {
        id = UUID()
        self.category = category
        self.hours = hours ?? category?.defaultHours ?? 1
        skips = 0
        self.pinned = pinned
        self.pinnedFrom = pinned == nil ? nil : pinnedFrom
        passed = []
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

    // How far is too far. A shared interest is worth 3; these are per km.
    private static let kmFromHalfwayCost = 2.0
    private static let kmFromNeighbourCost = 2.5
    /// The furthest a place may be from either of you when you live close.
    private static let nearbyKm = 6.0
    /// How far past halfway a place may be, for two people further apart.
    private static let pastHalfwayKm = 2.0
    /// The same two, when neither of you asked to keep it walkable: "a short
    /// ride is fine" used to reach exactly as far as walking did. Ten
    /// kilometres is about 25 to 35 minutes by transit across a city.
    static let rideKm = 10.0
    private static let ridePastHalfwayKm = 3.0
    /// How much distance costs when a ride is fine, against walking: half, so
    /// a place across town that suits you both can win over the nearest one.
    private static let rideDistanceScale = 0.5
    /// At most this much, per place, to tell near-equals apart.
    private static let varietyNudge = 1.0
    /// What being in a plan you already sent this person costs a place.
    private static let alreadySharedCost = 2.0
    /// What coming first in Apple's answer is worth, falling to nothing for
    /// last: as much as an interest only one of you has. Enough to choose the
    /// place people go to over the one nobody does, not enough to outweigh
    /// what you both like.
    private static let prominenceWeight = 1.0
    /// What a stop earns for speaking to whichever of you the plan has not yet
    /// spoken to. About a kilometre's worth: enough to choose the bowling alley
    /// over the next café along, not enough to cross town for it.
    private static let otherPersonBonus = 2.0

    /// FNV-1a. The same number for the same words on every phone and every
    /// launch, which Swift's own `hashValue` deliberately is not.
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

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
    ///
    /// `alreadyShared` is the names of places in plans already sent to this
    /// person. They are not ruled out -- a favourite is a favourite -- but they
    /// come after somewhere new.
    ///
    /// `excluded` is places never to offer: the ones you said were "Not for
    /// us", and the ones taken off for everybody (`backend/032`).
    static func plan(
        you: Person,
        them: Person,
        time: DatePlan.TimeOfDay,
        day: PlanDay? = nil,
        venues: [Venue],
        items: [PlanItem],
        theirCentre: Coordinate? = nil,
        halfwayName: String? = nil,
        alreadyShared: Set<String> = [],
        excluded: Set<String> = []
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

        /// **Variety, without a dice roll on every draw.** Apple Maps calls
        /// every restaurant "restaurant", so to the planner they all score the
        /// same and the nearest one won every time -- and when two tied, the
        /// one first in the alphabet did. A small nudge per place, worked out
        /// from the two of you and the day, spreads the picks: a different
        /// pair, or another day, gets different places, while the plan on
        /// screen holds still and a Swap is still the next one along.
        let seed = "\(you.id)|\(them.id)|\(day?.iso ?? "")"
        func nudge(_ venue: Venue) -> Double {
            Double(stableHash(seed + "|" + venue.id) % 1000) / 1000 * Self.varietyNudge
        }

        func liking(_ venue: Venue) -> Double {
            3.0 * Double(venue.themes.intersection(shared).count)
                + 1.0 * Double(venue.themes.intersection(oneSided).count)
                + fit.score(venue)
                + Self.prominenceWeight * venue.prominence
                + nudge(venue)
                - (alreadyShared.contains(venue.name) ? Self.alreadySharedCost : 0)
        }

        /// Near halfway, and about as far for one of you as for the other.
        /// Weighed so that distance can win: at the old weights a shared
        /// interest was worth four kilometres, and a place across town that
        /// matched one beat everything round the corner.
        /// Distance counts in full when either of you wants to walk, and half
        /// when a ride is fine.
        let distanceScale = fit.walkable ? 1.0 : Self.rideDistanceScale

        func between(_ venue: Venue) -> Double {
            var cost = 0.0
            if let middle { cost += distanceScale * Self.kmFromHalfwayCost * km(middle, venue.coordinate) }
            if let yourPoint, let theirPoint {
                cost += 1.0 * abs(km(yourPoint, venue.coordinate) - km(theirPoint, venue.coordinate))
            }
            return cost
        }

        /// **Never far from either of you.** No further from the one it is
        /// further from than halfway plus a little -- or, for two people who
        /// live close, than a short trip. Without it a plan reached as far as
        /// the search did, which in a quiet place was twenty kilometres. A
        /// short trip is further when a ride is fine (`rideKm`).
        let nearby = fit.walkable ? Self.nearbyKm : Self.rideKm
        let pastHalfway = fit.walkable ? Self.pastHalfwayKm : Self.ridePastHalfwayKm
        let reachLimit: Double? = {
            switch (yourPoint, theirPoint) {
            case let (a?, b?): return max(nearby, km(a, b) / 2 + pastHalfway)
            case (_?, nil), (nil, _?): return nearby
            default: return nil
            }
        }()
        func withinReach(_ venue: Venue) -> Bool {
            guard let reachLimit else { return true }
            return [yourPoint, theirPoint].compactMap { $0 }
                .allSatisfy { km($0, venue.coordinate) <= reachLimit }
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
                    && withinReach($0)
                    && $0.openingHours.covers(from: window.start, to: window.end)
                    && !used.contains($0.id) && !excluded.contains($0.id) && fit.allows($0)
            }
        }

        func pick(_ pool: [Venue], skips: Int, passing passed: Set<String> = [],
                  by score: (Venue) -> Double) -> Venue? {
            let fresh = pool.filter { !passed.contains($0.id) }
            let ranked = (fresh.isEmpty ? pool : fresh).sorted {
                let a = score($0), b = score($1)
                return a == b ? stableHash($0.id) < stableHash($1.id) : a > b
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
            for (index, item) in filled.enumerated() where index != anchorIndex && item.pinned == nil {
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

        // Kept places first: they are where they are, and the rest is placed
        // around them.
        var chosen: [Int: Venue] = [:]
        for (index, item) in filled.enumerated() {
            if let pinned = item.pinned, !excluded.contains(pinned.id) { chosen[index] = pinned }
        }
        let keptIDs = Set(chosen.values.map(\.id))

        let anchors = candidates(anchorCategory, at: anchorIndex, besides: keptIDs)
        let reachable = fit.walkable && filled.count > 1 ? anchors.filter(hasCompany) : anchors
        let anchorPool = reachable.isEmpty ? anchors : reachable
        let anchor = chosen[anchorIndex]
            ?? pick(anchorPool, skips: filled[anchorIndex].skips, passing: filled[anchorIndex].passed) {
                liking($0) - between($0)
            }

        /// Every other stop is placed beside one already placed: outward from
        /// the anchor, each near the stop on the anchor's side of it. Near the
        /// anchor alone was not enough -- two cafés either side of a park are
        /// each a walk from the park and not from each other, and with items in
        /// any order a walkable date had a train in it.
        func score(_ venue: Venue, near reference: Venue?) -> Double {
            guard let reference else { return liking(venue) - between(venue) }
            return liking(venue)
                - distanceScale * Self.kmFromNeighbourCost * km(reference.coordinate, venue.coordinate)
        }

        /// "Keep it walkable": only what is a walk from that stop. It gives way
        /// only when nothing at all is in reach -- and then the leg says "by
        /// transit", so the plan never pretends.
        func inReach(_ pool: [Venue], of reference: Venue?) -> [Venue] {
            guard fit.walkable, let reference else { return pool }
            let near = pool.filter { travel(km(reference.coordinate, $0.coordinate)).onFoot }
            return near.isEmpty ? pool : near
        }

        /// **Both of you, not whoever's interests the map happens to suit.**
        /// Scoring each place alone -- three for something you share, one for
        /// something either of you likes -- let a whole plan be about one
        /// person: one of a real pair wrote "Cooking", the restaurants all
        /// matched it, and nothing the other wrote got a stop. So once the plan speaks to one of
        /// you, the next stop earns `otherPersonBonus` for speaking to the
        /// other. Something you share speaks to both.
        let yoursOnly = Set(yours.keys).subtracting(shared)
        let theirsOnly = Set(theirs.keys).subtracting(shared)
        func speaksTo(_ venue: Venue) -> (you: Bool, them: Bool) {
            let both = !venue.themes.isDisjoint(with: shared)
            return (both || !venue.themes.isDisjoint(with: yoursOnly),
                    both || !venue.themes.isDisjoint(with: theirsOnly))
        }
        func balance(_ venue: Venue) -> Double {
            let placed = chosen.values
            let youHeard = placed.contains { speaksTo($0).you }
            let theyHeard = placed.contains { speaksTo($0).them }
            let this = speaksTo(venue)
            return (this.you && !youHeard ? Self.otherPersonBonus : 0)
                + (this.them && !theyHeard ? Self.otherPersonBonus : 0)
        }

        var placedNear: [Int: Venue] = [:]
        /// How many other places each stop could swap to.
        var alternatives: [Int: Int] = [
            anchorIndex: anchorPool.filter { $0.id != anchor?.id }.count
        ]
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
            let kept = filled[index].pinned != nil && chosen[index] != nil
            let used = Set(chosen.filter { $0.key != index }.values.map(\.id))
            let pool = notBesideAWalk(inReach(candidates(category, at: index, besides: used),
                                              of: reference),
                                      at: index)
            if kept {
                alternatives[index] = pool.filter { $0.id != chosen[index]?.id }.count
                continue
            }
            if let venue = pick(pool, skips: filled[index].skips, passing: filled[index].passed,
                                by: { score($0, near: reference) + balance($0) }) {
                chosen[index] = venue
                alternatives[index] = pool.filter { $0.id != venue.id }.count
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
                // A kept place says where it came from; it was not chosen here.
                reason: item.pinned?.id == venue.id
                    ? (item.pinnedFrom ?? "From the plan that was sent.")
                    : reason(for: venue, near: near,
                             shared: shared, you: you, yours: yours,
                             them: them, theirs: theirs, yourName: "You"),
                sharedReason: reason(for: venue, near: near,
                                     shared: shared, you: you, yours: yours,
                                     them: them, theirs: theirs, yourName: you.name),
                canSwap: (alternatives[index] ?? 0) > 0,
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

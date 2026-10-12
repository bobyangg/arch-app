import CoreLocation
import MapKit

/// Somewhere to go, from Apple Maps, around the point halfway between two people.
///
/// **This replaces `VenueLibrary` in the real build, because the library is
/// Brooklyn.** Thirty invented and real places in one borough were enough to
/// build the planner against, and useless to everybody who does not live there --
/// which, with Arch in Canada, is everybody. `MKLocalSearch` is on every iPhone,
/// needs no key and no contract, and knows the cafés of Moose Jaw.
///
/// **Apple Maps says what a place is; Arch decides what it is for.** A search by
/// category comes back with a name, a position and a category, and nothing about
/// whether it suits a first date. Each category is mapped once, below, to the
/// same things `VenueLibrary` writes by hand -- a kind, the themes it speaks to,
/// and the times of day it works for -- and the place's own
/// name adds any theme it plainly names ("Jazz", "Books"). `DatePlanner` then
/// ranks them exactly as it ranked the library, and does not know the difference.
///
/// **Opening hours are not something MapKit tells an app**, so a plan can name a
/// café that is shut on Sundays. The screen says to check, rather than pretend.
/// Nor are ratings or review counts: Apple keeps both inside Maps.
///
/// **Not everything Apple returns is somewhere to go.** A search for bookshops
/// in the "store" category came back with a ticket office and a shopping mall,
/// and the planner offered them as the main thing of a date. Every result is
/// now checked: its own category has to be one that was asked for, a search
/// by words has to find those words in the name, and names that are never a
/// date -- box offices, malls, stations -- are left out.
enum VenueSearch {

    /// What the planner needs for one person: where they are, in the only
    /// precision their profile has, and the places around the middle.
    struct Nearby: Equatable {
        /// The centre of their neighbourhood. Nil when Apple could not place it.
        let theirCentre: Coordinate?
        /// The neighbourhood at the halfway point, in words.
        let halfway: String?
        let venues: [Venue]
    }

    /// Nil when Apple Maps could not be reached at all. An empty `venues` means it
    /// was reached and found nowhere -- a different thing to say.
    @MainActor
    static func nearby(you: Person, them: Person) async -> Nearby? {
        // Theirs is the neighbourhood's centre and never anything finer, as the
        // planner has always promised. A profile from the server carries the
        // neighbourhood's words and no position, so the words are looked up.
        let theirCentre: Coordinate?
        if let known = them.place?.centre {
            theirCentre = known
        } else {
            theirCentre = await centre(of: them.place)
        }
        let yourPoint: Coordinate?
        if let known = you.matchPoint {
            yourPoint = known
        } else {
            yourPoint = await centre(of: you.place)
        }

        guard let middle = DatePlanner.middle(yourPoint, theirCentre) else {
            return Nearby(theirCentre: theirCentre, halfway: nil, venues: [])
        }

        // Close first, then wider -- but never wide. A city has enough within
        // a couple of kilometres; a small town gets its own few places rather
        // than the next town's. This went to twenty kilometres, and the
        // planner took what it found.
        let cuisines = cuisines(for: "\(you.id)|\(them.id)")
        var found: [Venue]?
        // Two rings rather than three: there are about twenty searches a ring
        // now (more with iOS 18's categories), and Apple Maps turns an app away
        // past about fifty a minute. The second ring runs only when the first
        // found too little, which in a city it rarely does.
        for radius in [3_000.0, 8_000.0] {
            guard let venues = await venues(around: middle, radius: radius, cuisines: cuisines) else {
                // Unreachable, or throttled: say so rather than show half a list.
                if found == nil { return nil }
                break
            }
            found = venues
            if isEnough(venues) { break }
        }

        var kept: [Venue] = []
        for venue in found ?? [] {
            if await isNamedForACornerElsewhere(venue, near: middle) { continue }
            kept.append(venue)
        }

        return Nearby(theirCentre: theirCentre,
                      halfway: await neighbourhood(at: middle),
                      venues: kept)
    }

    // MARK: Places named for somewhere else

    /// What Apple has answered about a name, so each is asked once a launch.
    @MainActor private static var cornerAnswers: [String: Bool] = [:]

    /// **"Jane N Finch", in the Financial District.** Apple Maps lists a live
    /// venue downtown under the name of a neighbourhood sixteen kilometres
    /// north-west -- the corner of Jane Street and Finch Avenue -- and to
    /// anybody from Toronto a plan that says "Jane N Finch" says the wrong end
    /// of the city, whatever the address underneath.
    ///
    /// No rule about words can tell that name from "Snakes & Lattes", so this
    /// asks the place it would be confused with. A name shaped like a corner --
    /// two words joined by "and", "&", "n" or "+", with nothing saying what the
    /// business is -- is looked up as an address near here. If Apple answers
    /// with a street corner or a neighbourhood of that name more than a
    /// kilometre from where the place is listed, the place is named for
    /// somewhere else and is left out. "Snakes & Lattes" is no corner, and a
    /// bar called "Jane & Finch" *at* Jane and Finch is where its name says.
    @MainActor
    private static func isNamedForACornerElsewhere(_ venue: Venue, near point: Coordinate) async -> Bool {
        guard let words = cornerWords(venue.name) else { return false }
        let key = words.joined(separator: "|") + String(format: "|%.2f|%.2f", venue.coordinate.latitude,
                                                         venue.coordinate.longitude)
        if let known = cornerAnswers[key] { return known }

        let geocoder = CLGeocoder()
        defer { withExtendedLifetime(geocoder) {} }
        let area = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
            radius: 50_000, identifier: "arch.planner.corner"
        )
        let marks = (try? await geocoder.geocodeAddressString(
            "\(words[0]) and \(words[1])", in: area, preferredLocale: nil
        )) ?? []

        let elsewhere = marks.contains { mark in
            guard let location = mark.location else { return false }
            let named = [mark.name, mark.thoroughfare, mark.subLocality]
                .compactMap { $0?.lowercased() }.joined(separator: " ")
            guard words.allSatisfy({ named.contains($0) }) else { return false }
            let isCorner = isStreetCorner(mark.name)
            let isNeighbourhood = mark.subLocality.map { sub in
                words.allSatisfy { sub.lowercased().contains($0) }
            } ?? false
            guard isCorner || isNeighbourhood else { return false }
            let there = Coordinate(latitude: location.coordinate.latitude,
                                   longitude: location.coordinate.longitude)
            return DatePlanner.km(there, venue.coordinate) > 1
        }
        cornerAnswers[key] = elsewhere
        return elsewhere
    }

    /// "Jane St & Finch Ave W": two streets, each with its kind of street, and
    /// an "&" between. A business with "&" in its name -- "Snakes & Lattes" --
    /// has no street on either side.
    private static func isStreetCorner(_ name: String?) -> Bool {
        guard let name else { return false }
        let sides = name.lowercased().components(separatedBy: "&")
        guard sides.count == 2 else { return false }
        return sides.allSatisfy { side in
            side.split { !$0.isLetter }.contains { streetKinds.contains(String($0)) }
        }
    }

    private static let streetKinds: Set<String> = [
        "st", "street", "ave", "avenue", "rd", "road", "blvd", "boulevard", "dr", "drive",
        "cres", "crescent", "pkwy", "parkway", "hwy", "highway", "way", "ln", "lane", "ct",
        "court", "pl", "place", "line", "trail", "gate", "terrace", "row", "sq", "square",
    ]

    /// The two words of a name shaped like a corner -- "Jane N Finch", "Yonge &
    /// Dundas" -- or nil. Three parts, the middle one a joining word, and
    /// nothing that says what kind of business it is.
    private static func cornerWords(_ name: String) -> [String]? {
        let parts = name.lowercased()
            .split { !$0.isLetter && $0 != "&" && $0 != "+" }
            .map(String.init)
        guard parts.count == 3, ["and", "&", "n", "+"].contains(parts[1]),
              parts[0].count > 2, parts[2].count > 2,
              !parts.contains(where: { businessWords.contains($0) })
        else { return nil }
        return [parts[0], parts[2]]
    }

    /// Enough to plan with: somewhere to eat or drink, and something to do.
    private static func isEnough(_ venues: [Venue]) -> Bool {
        DatePlan.Category.allCases.allSatisfy { category in
            venues.contains { $0.kind.category == category }
        }
    }

    // MARK: Categories

    /// One search per line, so that restaurants -- which a city has hundreds of
    /// -- cannot crowd out the one library. Each line is what a place in those
    /// categories is to the planner.
    private struct Group {
        let categories: [MKPointOfInterestCategory]
        /// For the few things with no category of their own, like bookshops.
        var query: String? = nil
        /// The name has to contain one of these, or it is not what was
        /// searched for -- a bookshop says "book"; a park worth going to says
        /// "park", "garden", "trail".
        var nameHas: [String]? = nil
        /// Names with one of these are left out, unless they also have one of
        /// `unlessHas`: "Waterfall Stage" goes, "Stage Theatre" stays.
        var rejects: [String] = []
        var unlessHas: [String] = []
        let kind: Venue.Kind
        let themes: Set<DateTheme>
        let times: Set<DatePlan.TimeOfDay>
        /// How many to keep. Restaurants all look alike to the planner, so it
        /// needs more of them to choose between.
        var keep = 10
    }

    /// What kinds of food to search for by name, besides "restaurant": three a
    /// pair, from this list, so two people do not get the same handful of
    /// places every time and different pairs get different ones.
    private static let cuisineQueries = ["ramen", "tacos", "pizza", "dumplings", "brunch",
                                         "thai", "sushi", "pho", "falafel", "curry"]

    private static func cuisines(for seed: String) -> [String] {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        let start = Int(hash % UInt64(cuisineQueries.count))
        return (0..<3).map { cuisineQueries[(start + $0 * 3) % cuisineQueries.count] }
    }

    /// **Asked for as things to do, not as everything on the map.** "Park" and
    /// "theater" alone brought back every parkette, every corner plaza named
    /// for its intersection, and outdoor stages with nothing on -- real places
    /// in Apple's eyes, and nowhere to take somebody. So the outdoor searches
    /// keep only places whose names say they are somewhere to go, and the
    /// rest of the list is made of the things people actually do on a date:
    /// films, bowling, galleries, comedy, an aquarium.
    private static func groups(cuisines: [String]) -> [Group] {
        var shows: [MKPointOfInterestCategory] = [.theater]
        var dayOut: [MKPointOfInterestCategory] = [.aquarium, .zoo, .amusementPark]
        if #available(iOS 18.0, *) {
            shows.append(.musicVenue)
            dayOut.append(.planetarium)
        }
        var groups = [
            Group(categories: [.cafe, .bakery], kind: .coffee,
                  themes: [.food], times: [.afternoon]),
            Group(categories: [.park, .nationalPark], nameHas: destinationWords, rejects: notAnOuting,
                  kind: .park,
                  themes: [.outdoors], times: [.afternoon]),
            Group(categories: [.beach, .marina], nameHas: destinationWords, rejects: notAnOuting,
                  kind: .walk,
                  themes: [.outdoors], times: [.afternoon, .evening]),
            Group(categories: [.museum], kind: .museum,
                  themes: [.craft, .buildings], times: [.afternoon]),
            Group(categories: [.library], kind: .library,
                  themes: [.words, .buildings], times: [.afternoon]),
            Group(categories: [.restaurant], kind: .food,
                  themes: [.food], times: [.afternoon, .evening], keep: 25),
            Group(categories: [.brewery, .winery, .nightlife], kind: .bar,
                  themes: [.food, .night], times: [.evening]),
            Group(categories: [.store], query: "bookstore", nameHas: ["book", "librair", "librer"],
                  kind: .shop, themes: [.words], times: [.afternoon]),
            Group(categories: [.store], query: "record store", nameHas: ["record", "vinyl", "disque"],
                  kind: .shop, themes: [.sound], times: [.afternoon]),
            // "Something live": a performance rather than a bar, so "I don't
            // drink" leaves it in. An outdoor stage is not one unless its
            // name says theatre -- with nothing on, it is a lawn.
            Group(categories: shows, rejects: outdoorStageWords, unlessHas: ["theatre", "theater", "playhouse", "hall", "club"],
                  kind: .show, themes: [.words, .sound], times: [.evening]),
            Group(categories: [.movieTheater], kind: .cinema,
                  themes: [.craft], times: [.afternoon, .evening]),
            Group(categories: dayOut, kind: .attraction,
                  themes: [.play], times: [.afternoon]),
            Group(categories: [.museum, .store], query: "art gallery", nameHas: ["gallery", "galerie", "art"],
                  kind: .museum, themes: [.craft], times: [.afternoon]),
            Group(categories: [.nightlife, .theater], query: "comedy club",
                  nameHas: ["comedy", "laugh", "improv", "funny", "comic"],
                  kind: .show, themes: [.words, .night], times: [.evening]),
            Group(categories: [.amusementPark, .store, .nightlife], query: "escape room", nameHas: ["escape"],
                  kind: .play, themes: [.play], times: [.afternoon, .evening]),
            // Games, for the people who write "Gaming" or "arcade" -- among the
            // commonest interests anybody writes. Held to the same checks as
            // everything else: Apple's own category, and a name that says so.
            Group(categories: [.amusementPark, .nightlife, .store], query: "arcade",
                  nameHas: ["arcade", "barcade", "pinball", "game", "pixel", "token"],
                  kind: .play, themes: [.play], times: [.afternoon, .evening]),
            Group(categories: [.cafe, .restaurant, .store, .nightlife], query: "board game cafe",
                  nameHas: ["game", "board", "dice", "meeple", "snakes"],
                  kind: .play, themes: [.play, .food], times: [.afternoon, .evening]),
        ]
        // Bowling, mini golf, go-karts, climbing, skating: categories of their
        // own from iOS 18. Before that, the escape-room search is the one
        // game on the list.
        if #available(iOS 18.0, *) {
            groups.append(Group(categories: [.bowling, .miniGolf, .goKart, .rockClimbing, .skating],
                                kind: .play, themes: [.play, .active], times: [.afternoon, .evening]))
        }
        // A restaurant search by cuisine finds places the plain one ranks too
        // low to return. The name need not say "ramen" -- the category does
        // the checking.
        for cuisine in cuisines {
            groups.append(Group(categories: [.restaurant], query: "\(cuisine) restaurant", kind: .food,
                                themes: [.food], times: [.afternoon, .evening], keep: 8))
        }
        return groups
    }

    /// What a park, a beach or a waterfront has in its name when it is
    /// somewhere to spend an afternoon. "Jane and Finch" -- a corner, filed as
    /// a park -- has none of them.
    private static let destinationWords = [
        "park", "garden", "gardens", "trail", "beach", "waterfront", "conservation",
        "ravine", "island", "pier", "harbour", "harbor", "boardwalk", "lake", "falls",
        "forest", "woods", "valley", "bluffs", "botanical", "arboretum", "marina", "quay",
    ]

    /// An outdoor stage, bandshell or pavilion: a place for an event, and
    /// with no event on, nowhere in particular.
    private static let outdoorStageWords = [
        "stage", "bandshell", "band shell", "amphitheatre", "amphitheater", "pavilion", "gazebo",
    ]

    /// Words in a name that mean it is not somewhere to spend part of a date:
    /// a ticket seller, a mall, a station, an office. Matched as whole words,
    /// in every search -- so nothing here may be a word a good café or
    /// restaurant could have in its name.
    private static let notAPlace: [String] = [
        "ticketmaster", "box office", "tickets", "mall", "plaza", "shopping centre",
        "shopping center", "outlet", "station", "terminal", "parking", "headquarters",
        "office", "offices", "corporate", "warehouse", "distribution", "wholesale",
        "gas", "atm", "bank", "clinic", "hospital", "pharmacy", "school", "church",
    ]

    /// Outdoors only: a park by name that is not an afternoon -- a parkette,
    /// a playground, a dog run, a square, a statue.
    private static let notAnOuting = [
        "parkette", "playground", "splash pad", "dog park", "off leash", "square",
        "cenotaph", "monument", "statue", "fountain",
    ]

    /// Somewhere to go, by its name and Apple's own category for it.
    private static func isAPlace(_ item: MKMapItem, name: String, group: Group) -> Bool {
        // Apple's category has to be one this search asked for. A result with
        // none at all is an address or an area -- an intersection, a
        // neighbourhood -- not a place.
        guard let category = item.pointOfInterestCategory,
              group.categories.contains(category) else { return false }
        let lower = name.lowercased()
        let wordsInName = " " + lower.split { !$0.isLetter }.joined(separator: " ") + " "
        func has(_ word: String) -> Bool { wordsInName.contains(" " + word + " ") }
        if let words = group.nameHas, !words.contains(where: { lower.contains($0) }) { return false }
        if group.rejects.contains(where: has), !group.unlessHas.contains(where: { lower.contains($0) }) {
            return false
        }
        if isAnArea(item, lower: lower) { return false }
        return !notAPlace.contains(where: has)
    }

    /// **A neighbourhood or a street corner that Apple has filed as a place.**
    /// "Jane and Finch" is both -- a neighbourhood named for the corner of Jane
    /// Street and Finch Avenue -- and Apple Maps gives it a category, so it
    /// came back from a search for things to do. Bob's name check kept it out
    /// of parks; this keeps it, and anything like it, out of every search:
    ///
    /// - named after its own neighbourhood or town ("Jane and Finch" in Jane and
    ///   Finch, "Liberty Village" in Liberty Village), or
    /// - named after its own street and another, joined by "and" or "&"
    ///   ("Jane and Finch" on Jane Street). The street has to be its own, so
    ///   "Snakes & Lattes" and "Salt and Pepper" -- real places with "and" in
    ///   their names -- are left alone, and so is anything whose name says
    ///   what it is ("Bloor & Spadina Café").
    private static func isAnArea(_ item: MKMapItem, lower: String) -> Bool {
        let mark = item.placemark
        let areaNames = [mark.subLocality, mark.locality, mark.subAdministrativeArea]
            .compactMap { $0?.lowercased() }
        if areaNames.contains(lower) { return true }

        let words = lower.split { !$0.isLetter }.map(String.init)
        let isJoined = words.contains("and") || lower.contains("&")
        guard isJoined, words.count <= 5,
              !words.contains(where: { businessWords.contains($0) }) else { return false }
        // The first word of the street it is on: "jane" for Jane Street.
        guard let street = mark.thoroughfare?.lowercased()
                .split(whereSeparator: { !$0.isLetter }).first.map(String.init),
              street.count > 2 else { return false }
        return words.contains(street)
    }

    /// Words that say a name belongs to a business, even when it is named for
    /// the corner it is on.
    private static let businessWords: Set<String> = [
        "cafe", "café", "coffee", "bar", "grill", "kitchen", "restaurant", "pub", "bistro",
        "eatery", "bakery", "diner", "tavern", "brewery", "books", "records", "gallery",
        "theatre", "theater", "cinema", "lanes", "bowl", "bowling", "arcade", "club", "house",
    ]

    /// Every group at once, around one point. Nil if any search failed outright,
    /// because a plan built from the half that answered would be quietly wrong.
    private static func venues(around point: Coordinate, radius: Double,
                               cuisines: [String]) async -> [Venue]? {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
            latitudinalMeters: radius * 2, longitudinalMeters: radius * 2
        )
        let groups = groups(cuisines: cuisines)
        let results = await withTaskGroup(of: (Int, [Venue]?).self) { tasks in
            for (index, group) in groups.enumerated() {
                tasks.addTask { (index, await search(group, in: region)) }
            }
            var results = [[Venue]?](repeating: nil, count: groups.count)
            for await (index, venues) in tasks { results[index] = venues }
            return results
        }
        guard results.allSatisfy({ $0 != nil }) else { return nil }

        // In group order, each place once: a brewery that is also a restaurant
        // keeps whichever line found it first.
        //
        // **And inside the area that was asked about.** A search by name --
        // "ramen restaurant", "bookstore" -- takes the region as a hint, not a
        // fence, and answers with the best match in the city: a place sixteen
        // kilometres away is a fine answer to Apple and a wrong one here. The
        // planner limits how far a stop may be from either of you, but only
        // when it knows where you both are; this holds whether it does or not.
        let limitKm = radius / 1000 * 1.25
        var seen = Set<String>()
        return results.compactMap { $0 }.joined().filter {
            DatePlanner.km(point, $0.coordinate) <= limitKm && seen.insert($0.id).inserted
        }
    }

    private static func search(_ group: Group, in region: MKCoordinateRegion) async -> [Venue]? {
        let filter = MKPointOfInterestFilter(including: group.categories)
        let items: [MKMapItem]
        do {
            if let query = group.query {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.resultTypes = .pointOfInterest
                request.pointOfInterestFilter = filter
                request.region = region
                // A search by name takes the region as a hint and answers with
                // the best match in the city. From iOS 18 it can be told to
                // stay inside; before that, `venues(around:)` drops what does
                // not.
                if #available(iOS 18.0, *) {
                    request.regionPriority = .required
                }
                items = try await MKLocalSearch(request: request).start().mapItems
            } else {
                let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
                request.pointOfInterestFilter = filter
                items = try await MKLocalSearch(request: request).start().mapItems
            }
        } catch let error as MKError where error.code == .placemarkNotFound {
            // Searched and found nothing of this kind here. Not a failure.
            return []
        } catch {
            return nil
        }
        // Checked first, then counted: ten real places of each kind (more
        // restaurants) keeps one kind from outnumbering the rest in a big city.
        return Array(items.compactMap { venue(from: $0, group: group) }.prefix(group.keep))
    }

    private static func venue(from item: MKMapItem, group: Group) -> Venue? {
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, isAPlace(item, name: name, group: group) else { return nil }
        let mark = item.placemark
        let point = Coordinate(latitude: mark.coordinate.latitude,
                               longitude: mark.coordinate.longitude)
        let neighbourhood = mark.subLocality ?? mark.locality ?? ""
        return Venue(
            id: String(format: "mk:%@|%.4f|%.4f", name, point.latitude, point.longitude),
            name: name,
            kind: group.kind,
            neighbourhood: neighbourhood,
            coordinate: point,
            // "Jazz Bar", "Paper & Ink Books": the name says what the category
            // cannot.
            themes: group.themes.union(DateTheme.themes(in: name)),
            times: group.times
        )
    }

    // MARK: Geocoding

    /// The centre of a neighbourhood, from its words. The geocoder is held in a
    /// local for the life of the request, for the reason `PlaceSearch` gives.
    private static func centre(of place: Place?) async -> Coordinate? {
        guard let place, !place.name.isEmpty else { return nil }
        let words = place.city.isEmpty ? place.name : "\(place.name), \(place.city)"
        let geocoder = CLGeocoder()
        defer { withExtendedLifetime(geocoder) {} }
        guard let mark = try? await geocoder.geocodeAddressString(words).first,
              let location = mark.location else { return nil }
        return Coordinate(latitude: location.coordinate.latitude,
                          longitude: location.coordinate.longitude).coarsened
    }

    /// What to call the halfway point: its neighbourhood, or its town.
    private static func neighbourhood(at point: Coordinate) async -> String? {
        let geocoder = CLGeocoder()
        defer { withExtendedLifetime(geocoder) {} }
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let mark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        return mark.subLocality ?? mark.locality
    }
}

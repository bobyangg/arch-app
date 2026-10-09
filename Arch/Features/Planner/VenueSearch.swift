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

        // Close first, then wider. A city has enough within a couple of
        // kilometres for a date on foot; a small town may need the whole town.
        var found: [Venue]?
        for radius in [2_500.0, 8_000.0, 20_000.0] {
            guard let venues = await venues(around: middle, radius: radius) else {
                // Unreachable, or throttled: say so rather than show half a list.
                if found == nil { return nil }
                break
            }
            found = venues
            if isEnough(venues) { break }
        }

        return Nearby(theirCentre: theirCentre,
                      halfway: await neighbourhood(at: middle),
                      venues: found ?? [])
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
        let kind: Venue.Kind
        let themes: Set<DateTheme>
        let times: Set<DatePlan.TimeOfDay>
    }

    private static var groups: [Group] {
        var groups = [
            Group(categories: [.cafe, .bakery], kind: .coffee,
                  themes: [.food], times: [.afternoon]),
            Group(categories: [.park, .nationalPark], kind: .park,
                  themes: [.outdoors], times: [.afternoon]),
            Group(categories: [.beach, .marina], kind: .walk,
                  themes: [.outdoors], times: [.afternoon, .evening]),
            Group(categories: [.museum], kind: .museum,
                  themes: [.craft, .buildings], times: [.afternoon]),
            Group(categories: [.library], kind: .library,
                  themes: [.words, .buildings], times: [.afternoon]),
            Group(categories: [.restaurant], kind: .food,
                  themes: [.food], times: [.afternoon, .evening]),
            Group(categories: [.brewery, .winery, .nightlife], kind: .bar,
                  themes: [.food, .night], times: [.evening]),
            Group(categories: [.store], query: "bookstore", kind: .shop,
                  themes: [.words], times: [.afternoon]),
            Group(categories: [.store], query: "record store", kind: .shop,
                  themes: [.sound], times: [.afternoon]),
            // "Something live": a performance rather than a bar, so "I don't
            // drink" leaves it in.
            Group(categories: [.theater], kind: .show,
                  themes: [.words, .sound], times: [.evening]),
        ]
        if #available(iOS 18.0, *) {
            groups.append(Group(categories: [.musicVenue], kind: .show,
                                themes: [.sound, .night], times: [.evening]))
        }
        return groups
    }

    /// Every group at once, around one point. Nil if any search failed outright,
    /// because a plan built from the half that answered would be quietly wrong.
    private static func venues(around point: Coordinate, radius: Double) async -> [Venue]? {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
            latitudinalMeters: radius * 2, longitudinalMeters: radius * 2
        )
        let groups = groups
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
        var seen = Set<String>()
        return results.compactMap { $0 }.joined().filter { seen.insert($0.id).inserted }
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
        // Ten of each is plenty to rank, and keeps one kind from outnumbering
        // the rest in a big city.
        return items.prefix(10).compactMap { venue(from: $0, group: group) }
    }

    private static func venue(from item: MKMapItem, group: Group) -> Venue? {
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
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

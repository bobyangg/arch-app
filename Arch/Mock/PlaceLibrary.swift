import Foundation

/// A point on the earth, stored no more precisely than Arch needs.
///
/// **Everything is rounded to `grid` before it is kept.** At 0.01° that is a little
/// over a kilometre — enough to filter by distance, not enough to say which street
/// somebody lives on. The precise fix a phone hands over is used to pick the square
/// and then thrown away; it is never stored and never sent anywhere.
struct Coordinate: Hashable {
    var latitude: Double
    var longitude: Double

    /// ~1.1km of latitude. The only precision Arch ever holds.
    static let grid = 0.01

    /// Snapped to the grid. Call this on anything that came from a device.
    var coarsened: Coordinate {
        Coordinate(
            latitude: (latitude / Self.grid).rounded() * Self.grid,
            longitude: (longitude / Self.grid).rounded() * Self.grid
        )
    }

    /// Great-circle miles, by the haversine formula.
    ///
    /// Good to a fraction of a percent at these distances, and the filter it feeds
    /// starts at five miles — so the earth being an imperfect sphere is several
    /// orders of magnitude below anything that matters here.
    func miles(to other: Coordinate) -> Double {
        let earthRadius = 3958.8
        let φ1 = latitude * .pi / 180, φ2 = other.latitude * .pi / 180
        let dφ = (other.latitude - latitude) * .pi / 180
        let dλ = (other.longitude - longitude) * .pi / 180
        let a = sin(dφ / 2) * sin(dφ / 2)
            + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Somewhere a person says they live.
///
/// One type for two things that behave identically: a neighbourhood where
/// neighbourhoods are a thing, and a town where they are not. "Fort Greene,
/// Brooklyn" and "Hudson, New York" read the same way and sort into the same list,
/// so nothing in the app needs to know which kind it has.
struct Place: Identifiable, Hashable {
    let id: String
    /// The neighbourhood, or the town.
    let name: String
    /// What it sits inside: a borough, a city, a state, or a province.
    let city: String

    /// Where it is — when Arch knows.
    ///
    /// **Optional on purpose, and the reason is a privacy one.** A place rebuilt
    /// from a stored `place_id` has no coordinate, because the id deliberately
    /// does not carry one: `visible_profiles` publishes `place_id` and no
    /// position, so a latitude smuggled inside the id would be a latitude
    /// published to everybody who can see the profile. The coordinate lives in
    /// `coarse_lat`/`coarse_lon`, which only the matcher reads.
    ///
    /// Nothing on the display side ever touches this. The two places that do —
    /// creating a profile and editing one — are the two that have just been
    /// handed a real place, from the list or from a geocoder.
    let centre: Coordinate?

    /// What goes on the profile chip.
    var label: String { city.isEmpty ? name : "\(name), \(city)" }
}

extension Place {

    /// Marks an id as words rather than a row in `PlaceLibrary.all`.
    static let geocodedPrefix = "g:"

    /// A place that came from a geocoder rather than the bundled list.
    ///
    /// The id *is* the label, because there is no table to look it up in later:
    /// somebody in Moose Jaw is not in `all` and never will be, and the chip on
    /// their profile still has to say Moose Jaw. `place_id` is already the
    /// public display value in `visible_profiles`, so putting display words in
    /// it exposes nothing that column did not already expose.
    init(geocodedName name: String, city: String, centre: Coordinate?) {
        // The separators have to survive the round trip, so they cannot appear
        // inside a name. Neither occurs in a North American place name; this is
        // for whatever a geocoder does that I have not seen.
        func clean(_ text: String) -> String {
            text.replacingOccurrences(of: "|", with: " ")
                .replacingOccurrences(of: ":", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        let cleanName = clean(name), cleanCity = clean(city)
        self.init(
            id: "\(Place.geocodedPrefix)\(cleanName)|\(cleanCity)",
            name: cleanName,
            city: cleanCity,
            centre: centre
        )
    }

    /// The words back out of a geocoded id, or nil if it is not one.
    static func geocoded(fromID id: String) -> Place? {
        guard id.hasPrefix(geocodedPrefix) else { return nil }
        let body = id.dropFirst(geocodedPrefix.count)
        let parts = body.split(separator: "|", maxSplits: 1,
                               omittingEmptySubsequences: false)
        guard let name = parts.first, !name.isEmpty else { return nil }
        return Place(
            id: id,
            name: String(name),
            city: parts.count > 1 ? String(parts[1]) : "",
            centre: nil
        )
    }
}

/// The gazetteer the picker reads.
///
/// **This is the suggestion list, not the coverage.** Anywhere in the United
/// States or Canada can be chosen — `PlaceSearch` asks the device's own geocoder,
/// which knows every town in both and costs nothing. What stays here is the set
/// the picker offers before anybody types, the fixture the design build and the UI
/// tests run on, and the population the matcher simulation reads.
///
/// Coordinates are approximate centres, which is the point: they are the fallback
/// for somebody who did not give Arch their location, and they are never more
/// precise than the square `Coordinate.grid` would have rounded them to anyway.
enum PlaceLibrary {

    static let all: [Place] = [
        // Brooklyn
        place("bk-fort-greene", "Fort Greene", "Brooklyn", 40.691, -73.974),
        place("bk-gowanus", "Gowanus", "Brooklyn", 40.674, -73.989),
        place("bk-crown-heights", "Crown Heights", "Brooklyn", 40.668, -73.944),
        place("bk-bed-stuy", "Bed-Stuy", "Brooklyn", 40.687, -73.941),
        place("bk-sunset-park", "Sunset Park", "Brooklyn", 40.645, -74.012),
        place("bk-bushwick", "Bushwick", "Brooklyn", 40.694, -73.921),
        place("bk-greenpoint", "Greenpoint", "Brooklyn", 40.730, -73.951),
        place("bk-williamsburg", "Williamsburg", "Brooklyn", 40.714, -73.957),
        place("bk-park-slope", "Park Slope", "Brooklyn", 40.671, -73.978),
        place("bk-prospect-heights", "Prospect Heights", "Brooklyn", 40.677, -73.968),
        place("bk-carroll-gardens", "Carroll Gardens", "Brooklyn", 40.679, -73.999),
        place("bk-bay-ridge", "Bay Ridge", "Brooklyn", 40.626, -74.030),

        // Queens
        place("qn-astoria", "Astoria", "Queens", 40.764, -73.923),
        place("qn-ridgewood", "Ridgewood", "Queens", 40.708, -73.897),
        place("qn-long-island-city", "Long Island City", "Queens", 40.745, -73.949),
        place("qn-sunnyside", "Sunnyside", "Queens", 40.743, -73.920),
        place("qn-jackson-heights", "Jackson Heights", "Queens", 40.755, -73.883),
        place("qn-flushing", "Flushing", "Queens", 40.768, -73.833),

        // Manhattan
        place("mn-harlem", "Harlem", "Manhattan", 40.811, -73.946),
        place("mn-washington-heights", "Washington Heights", "Manhattan", 40.840, -73.940),
        place("mn-upper-west-side", "Upper West Side", "Manhattan", 40.787, -73.975),
        place("mn-east-village", "East Village", "Manhattan", 40.727, -73.982),
        place("mn-west-village", "West Village", "Manhattan", 40.736, -74.003),
        place("mn-lower-east-side", "Lower East Side", "Manhattan", 40.715, -73.984),

        // The Bronx
        place("bx-mott-haven", "Mott Haven", "The Bronx", 40.809, -73.923),
        place("bx-riverdale", "Riverdale", "The Bronx", 40.890, -73.912),

        // Staten Island
        place("si-st-george", "St. George", "Staten Island", 40.644, -74.077),

        // New Jersey — two miles from Manhattan and a different state, which is
        // exactly why the filter is a radius and not a city boundary.
        place("nj-jersey-city", "Jersey City", "New Jersey", 40.728, -74.078),
        place("nj-hoboken", "Hoboken", "New Jersey", 40.744, -74.032),

        // Towns, where a neighbourhood is not a thing anybody would name.
        place("ny-beacon", "Beacon", "New York", 41.505, -73.970),
        place("ny-hudson", "Hudson", "New York", 42.253, -73.791),
        place("ny-new-paltz", "New Paltz", "New York", 41.747, -74.087)
    ]

    /// Grouped for the picker, in the order `all` first mentions each city.
    static var groups: [(city: String, places: [Place])] {
        var order: [String] = []
        var byCity: [String: [Place]] = [:]
        for place in all {
            if byCity[place.city] == nil { order.append(place.city) }
            byCity[place.city, default: []].append(place)
        }
        return order.map { (city: $0, places: byCity[$0] ?? []) }
    }

    /// **Two kinds of id reach this, and both have to come back as words.** A
    /// row in `all` for anybody who picked from the list, and a geocoded id for
    /// everybody else — which is now most people, since the list covers one
    /// metro and the app covers two countries.
    static func place(matching id: String) -> Place? {
        all.first { $0.id == id } ?? Place.geocoded(fromID: id)
    }

    /// Case- and punctuation-insensitive, and it searches the city as well as the
    /// name — typing "brooklyn" should find everywhere in Brooklyn.
    static func search(_ text: String) -> [Place] {
        let needle = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }
        return all.filter { place in
            place.label
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(needle)
        }
    }

    /// The nearest row in the bundled list.
    ///
    /// **This is no longer how a device fix becomes a place, and using it that
    /// way was wrong the moment Arch left New York.** It searches thirty-two
    /// neighbourhoods, so a fix in Vancouver came back as Bay Ridge — the
    /// closest of them, two and a half thousand miles away, written onto a
    /// profile as fact. `PlaceSearch.place(at:)` asks the device's geocoder
    /// instead and knows the whole continent.
    ///
    /// It survives for the design build, which has no network and no geocoder,
    /// and where every mock profile is in New York anyway.
    static func nearest(to coordinate: Coordinate) -> Place? {
        all.min { a, b in
            (a.centre?.miles(to: coordinate) ?? .infinity)
                < (b.centre?.miles(to: coordinate) ?? .infinity)
        }
    }

    private static func place(
        _ id: String, _ name: String, _ city: String,
        _ latitude: Double, _ longitude: Double
    ) -> Place {
        Place(
            id: id, name: name, city: city,
            centre: Coordinate(latitude: latitude, longitude: longitude).coarsened
        )
    }
}

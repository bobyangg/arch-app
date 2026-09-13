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
    /// What it sits inside: a borough, a city, or a state.
    let city: String
    let centre: Coordinate

    /// What goes on the profile chip.
    var label: String { "\(name), \(city)" }
}

/// The gazetteer the picker reads.
///
/// A few dozen rows for one metro is the whole of it — no geocoding service, no map
/// tiles, no per-lookup bill. A real launch extends the list; nothing about the
/// shape changes.
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

    static func place(matching id: String) -> Place? {
        all.first { $0.id == id }
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

    /// What a device fix resolves to: the nearest place in the list.
    ///
    /// The coordinate is still stored separately and coarsened — this only picks
    /// the words that go on the profile, because "Bedford-Stuyvesant" from a
    /// geocoder is not what somebody who says "Bed-Stuy" wants on their profile.
    /// They can change it; that is what the picker is for.
    static func nearest(to coordinate: Coordinate) -> Place? {
        all.min { $0.centre.miles(to: coordinate) < $1.centre.miles(to: coordinate) }
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

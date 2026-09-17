import CoreLocation
import MapKit
import Observation

/// Finding anywhere in the United States or Canada, without shipping a gazetteer.
///
/// **The bundled list stopped being the answer the moment Arch left one metro.**
/// Thirty-two hand-written neighbourhoods work when the product is New York. For
/// two countries the choice is a static table of every town — which needs a
/// population cutoff, and everybody under it cannot sign up — or asking the
/// device, which already has all of it. `MKLocalSearch` is on every iPhone, costs
/// nothing, needs no key, and is never out of date.
///
/// **What comes back is cut down before it is kept.** A geocoder will happily
/// return a street address, and this reduces every result to a neighbourhood or a
/// town and the 0.01° square it sits in. Somebody who searches their own street
/// gets a better *coordinate* — which is what the distance filter reads — and the
/// same coarse *words* on the chip, which is all anybody else ever sees. The
/// precision goes where it is useful and not where it would be exposure.
///
/// `PlaceLibrary` stays, and is still the list under the search field: it is what
/// the design build and the UI tests run on, what the matcher simulation reads,
/// and a reasonable set of suggestions for the metro Arch actually launched in.
@MainActor
@Observable
final class PlaceSearch {

    /// What the screen underneath needs to know. Four cases rather than a
    /// `[Place]` and a `Bool`, because "typing", "nothing matched" and "the
    /// network is not there" are three different screens and two of them are
    /// empty lists.
    enum State: Equatable {
        case idle
        case searching
        case found
        /// The lookup itself failed — no network, or Apple's service refused.
        /// Distinct from finding nothing, because there is something to say
        /// about it and something to do about it.
        case unreachable
    }

    private(set) var results: [Place] = []
    private(set) var state: State = .idle

    /// The in-flight lookup, kept so the next keystroke can cancel it. Without
    /// this, results arrive in whatever order the network returns them and a
    /// slow request for "bro" overwrites a fast one for "brooklyn".
    private var lookup: Task<Void, Never>?

    /// Biases results towards North America. It is a hint, not a fence — Apple
    /// will still answer with Bristol — so the country check in
    /// `Place.init(_ placemark:)` is what actually holds the line.
    private static let northAmerica = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48, longitude: -97),
        span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 110)
    )

    /// Call on every keystroke. Debounced, so it is not a request per character.
    func search(_ text: String) {
        lookup?.cancel()

        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Two characters, because one matches most of the continent and the
        // answer is useless by the time it arrives.
        guard needle.count >= 2 else {
            results = []
            state = .idle
            return
        }

        state = .searching
        lookup = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let found = await PlaceSearch.lookUp(needle)

            guard !Task.isCancelled else { return }
            self?.results = found ?? []
            self?.state = found == nil ? .unreachable : .found
        }
    }

    /// Clears everything and stops whatever was in flight.
    func reset() {
        lookup?.cancel()
        lookup = nil
        results = []
        state = .idle
    }

    /// `nil` means the lookup failed. An empty array means it worked and there is
    /// nothing by that name in either country.
    private static func lookUp(_ needle: String) async -> [Place]? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = needle
        // Addresses and places, not businesses. Nobody lives in a coffee shop,
        // and a list of them under "where you live" reads as a mistake.
        request.resultTypes = [.address]
        request.region = northAmerica

        do {
            let response = try await MKLocalSearch(request: request).start()
            var seen = Set<String>()
            var places: [Place] = []
            for item in response.mapItems {
                guard let place = Place(item.placemark) else { continue }
                // Ten addresses on one street all reduce to the same
                // neighbourhood, and the same row ten times is not a list.
                guard seen.insert(place.id).inserted else { continue }
                places.append(place)
            }
            return places
        } catch {
            return nil
        }
    }

    /// The words for a point, for when somebody taps "Use my location".
    ///
    /// **This replaced `PlaceLibrary.nearest`, which became actively wrong.**
    /// `nearest` searched the bundled list, so a device fix in Vancouver came
    /// back as the closest of thirty-two New York neighbourhoods — Bay Ridge,
    /// two and a half thousand miles away, stated as fact on a profile.
    static func place(at coordinate: Coordinate) async -> Place? {
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let marks = try? await CLGeocoder().reverseGeocodeLocation(point) else {
            return nil
        }
        return marks.lazy.compactMap { Place($0) }.first
    }
}

extension Place {

    /// A geocoder's answer, reduced to the two words Arch keeps.
    ///
    /// Fails rather than guesses in two cases: outside the United States and
    /// Canada, and when the placemark has no town in it at all — a point in the
    /// middle of Lake Superior has a country and nothing else, and "Ontario,
    /// Ontario" is not a place somebody lives.
    init?(_ placemark: CLPlacemark) {
        guard let country = placemark.isoCountryCode,
              country == "US" || country == "CA" else { return nil }

        // `subAdministrativeArea` is the county, and it is the only thing an
        // unincorporated address has. Better than nothing, which is the
        // alternative.
        let town = placemark.locality ?? placemark.subAdministrativeArea
        let region = placemark.administrativeArea ?? placemark.country

        let name: String
        let city: String
        if let neighbourhood = placemark.subLocality, let town {
            // Bed-Stuy, Brooklyn. The shape the app was built around.
            name = neighbourhood
            city = town
        } else if let town {
            // Beacon, New York. Or Moose Jaw, Saskatchewan.
            name = town
            city = region ?? ""
        } else {
            return nil
        }

        let centre = placemark.location.map {
            Coordinate(latitude: $0.coordinate.latitude,
                       longitude: $0.coordinate.longitude).coarsened
        }
        self.init(geocodedName: name, city: city, centre: centre)
    }
}

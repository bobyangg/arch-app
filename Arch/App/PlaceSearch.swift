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
    ///
    /// **Two services, and the second is only ever asked when the first came
    /// back with nothing.** `MKLocalSearch` is built for search-as-you-type and
    /// is what every keystroke goes to. `CLGeocoder` is the better authority on
    /// whether a town exists at all, but Apple rate limits it per app and is
    /// explicit that it is not for per-keystroke use — so it is the second
    /// opinion on an empty answer and never the first.
    private static func lookUp(_ needle: String) async -> [Place]? {
        let mapped = await mapSearch(needle)
        if let mapped, !mapped.isEmpty { return mapped }
        if let geocoded = await geocode(needle), !geocoded.isEmpty { return geocoded }
        // nil when the map search itself failed, [] when it simply found nothing.
        return mapped
    }

    private static func mapSearch(_ needle: String) async -> [Place]? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = needle
        // Addresses and places, not businesses. Nobody lives in a coffee shop,
        // and a list of them under "where you live" reads as a mistake.
        request.resultTypes = [.address]
        request.region = northAmerica

        do {
            let response = try await MKLocalSearch(request: request).start()
            return reduce(response.mapItems.map(\.placemark))
        } catch {
            return nil
        }
    }

    /// The plain geocoder, for a town the map search did not think to offer.
    private static func geocode(_ needle: String) async -> [Place]? {
        let geocoder = CLGeocoder()
        defer { withExtendedLifetime(geocoder) {} }
        guard let marks = try? await geocoder.geocodeAddressString(needle) else {
            return nil
        }
        return reduce(marks)
    }

    /// Placemarks to rows: to the words Arch keeps, in either country, once each.
    private static func reduce(_ marks: [CLPlacemark]) -> [Place] {
        var seen = Set<String>()
        var places: [Place] = []
        for mark in marks {
            guard let place = Place(mark) else { continue }
            // Ten addresses on one street all reduce to the same neighbourhood,
            // and the same row ten times is not a list.
            guard seen.insert(place.id).inserted else { continue }
            places.append(place)
        }
        return places
    }

    /// The words for a point, for when somebody taps "Use my location".
    ///
    /// **This replaced `PlaceLibrary.nearest`, which became actively wrong.**
    /// `nearest` searched the bundled list, so a device fix in Vancouver came
    /// back as the closest of thirty-two New York neighbourhoods — Bay Ridge,
    /// two and a half thousand miles away, stated as fact on a profile.
    /// **The geocoder is held in a local on purpose, and `CLGeocoder()` written
    /// inline was the bug.** A temporary geocoder is released as soon as the call
    /// expression finishes, which is *before* the await resumes; `CLGeocoder`
    /// cancels its pending request on deinit, so the answer came back as a
    /// cancellation every time. On screen that was "Use my location" asking for
    /// permission, being granted it, and then finding nothing — twice, because
    /// tapping again did exactly the same thing. Apple's own documentation says
    /// to keep a strong reference for the life of the request; this is that.
    static func place(at coordinate: Coordinate) async -> Place? {
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        defer { withExtendedLifetime(geocoder) {} }
        guard let marks = try? await geocoder.reverseGeocodeLocation(point) else {
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
        } else if let area = placemark.administrativeArea {
            // No town of any kind: a rural address that sits between places. The
            // state or province is a poor chip and an honest one, and it beats
            // failing outright — a nil here is a button that did nothing, and
            // this screen has already been that once.
            name = area
            city = placemark.country ?? ""
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

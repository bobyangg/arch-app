import CoreLocation

/// One fix, coarsened, then forgotten.
///
/// **Arch asks for a location once and never watches.** There is no
/// `startUpdatingLocation` anywhere in here, no background mode, no significant-
/// change monitoring. Somebody taps "Use my location", iOS answers once, the point
/// is rounded to the 0.01° grid the rest of the app uses, and the manager is let
/// go. A dating app that tracked where you were would be a different product, and
/// the one thing it would be good at is the thing this one refuses to do.
///
/// **Coarsened before it is stored, not when it is shown.** `Coordinate.coarsened`
/// rounds to about a kilometre, and that rounding happens here — the fine value
/// exists inside this file for the length of one callback and is never handed to
/// anything that could keep it. `PlaceLibrary.nearest` then turns it into a
/// neighbourhood name, which is the only form anybody else ever sees.
///
/// **`whenInUse`, never `always`.** The one is enough for a picker and the other
/// would need a reason Arch does not have.
@MainActor
final class DeviceLocation: NSObject, CLLocationManagerDelegate {

    /// What came back, or why nothing did.
    enum Outcome {
        case fix(Coordinate)
        /// The person said no. Not an error, and not worth asking twice — the
        /// list underneath the button is the same list either way.
        case refused
        /// Location is off for the whole device, or restricted. Distinct from a
        /// refusal because there is nothing the reader can do about it here.
        case unavailable
    }

    private let manager = CLLocationManager()
    private var answer: ((Outcome) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        // A neighbourhood is the finest thing Arch stores, so asking for metres
        // would spend battery on precision that is thrown away a line later.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Ask once. The closure is called exactly once, whatever happens.
    func request(_ answer: @escaping (Outcome) -> Void) {
        self.answer = answer

        switch manager.authorizationStatus {
        case .notDetermined:
            // The prompt only appears if `NSLocationWhenInUseUsageDescription` is
            // in Info.plist. Without it iOS does not warn -- it terminates the
            // app.
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied:
            finish(.refused)
        case .restricted:
            finish(.unavailable)
        @unknown default:
            finish(.unavailable)
        }
    }

    private func finish(_ outcome: Outcome) {
        // Once, and then never again: a delegate can fire more than once, and a
        // second call would re-run whatever the caller does with the answer.
        let pending = answer
        answer = nil
        pending?(outcome)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                // Only now, because asking before the answer comes back gets
                // nothing and looks like a failure.
                self.manager.requestLocation()
            case .denied:
                self.finish(.refused)
            case .restricted:
                self.finish(.unavailable)
            case .notDetermined:
                break   // The prompt is still on screen.
            @unknown default:
                self.finish(.unavailable)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let last = locations.last else { return }
        let point = Coordinate(
            latitude: last.coordinate.latitude,
            longitude: last.coordinate.longitude
        )
        Task { @MainActor in
            // Coarsened on the way in. Nothing downstream ever sees the fine one.
            self.finish(.fix(point.coarsened))
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            // A failure is the same outcome as no permission as far as the screen
            // is concerned: the list is still there, and it is still the path.
            self.finish(.unavailable)
        }
    }
}

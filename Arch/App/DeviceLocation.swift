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

    /// **A delegate that never fires is the worst outcome of the three.**
    /// `requestLocation()` is documented to call back exactly once, and in
    /// practice it can sit there: indoors, on a device with no recent fix, or
    /// when a previous request was superseded. The closure then never runs, the
    /// button that is waiting on it shows nothing, and tapping it again does the
    /// same nothing -- which is precisely what this looked like on a phone.
    private var deadline: Task<Void, Never>?

    /// How long to wait before giving the answer that is available.
    ///
    /// Longer than a good fix takes and shorter than somebody will stare at a
    /// button wondering whether they missed the tap.
    private static let patience = Duration.seconds(12)

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
        startDeadline()

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
        deadline?.cancel()
        deadline = nil
        let pending = answer
        answer = nil
        pending?(outcome)
    }

    private func startDeadline() {
        deadline?.cancel()
        deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(for: DeviceLocation.patience)
            guard !Task.isCancelled else { return }
            self?.finishWithWhateverExists()
        }
    }

    /// The best answer available without waiting any longer.
    ///
    /// **`manager.location` is the fix iOS already has**, from whatever asked for
    /// one most recently -- Maps, the weather, this app a minute ago. It costs
    /// nothing, needs no new authorisation, and is accurate to far better than
    /// the kilometre Arch rounds to anyway. Using it is strictly better than
    /// telling somebody their phone does not know where it is while it plainly
    /// does.
    private func finishWithWhateverExists() {
        if let known = manager.location {
            finish(.fix(Coordinate(latitude: known.coordinate.latitude,
                                   longitude: known.coordinate.longitude).coarsened))
        } else {
            finish(.unavailable)
        }
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
            // A failure is not the end of it. `kCLErrorLocationUnknown` is common
            // and transient -- indoors, or a cold start -- and the phone very
            // often still holds a perfectly good recent fix.
            self.finishWithWhateverExists()
        }
    }
}

import CoreLocation
import Foundation

// MARK: - One location fix, on demand

/// Asks for a single fix, and asks for permission the first time it is used.
///
/// Deliberately not started at launch and deliberately when-in-use: the only
/// caller is the transit screen, which needs to know where you are at the
/// moment you open it and never otherwise.
@Observable
final class LocationFinder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    /// Long enough for a cold fix, short enough that the screen is not left
    /// hanging on it. Falling back is a perfectly good answer.
    private let patience: Duration = .seconds(8)

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// nil means refused, unavailable, or too slow — all of which mean the
    /// caller should use the home stop.
    func coordinate() async -> CLLocationCoordinate2D? {
        guard !isDenied else { return nil }

        return await withCheckedContinuation { continuation in
            waiting = continuation

            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }

            Task { [weak self, patience] in
                try? await Task.sleep(for: patience)
                self?.finish(nil)
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        guard let waiting else { return }
        self.waiting = nil
        waiting.resume(returning: coordinate)
    }

    // MARK: Delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard waiting != nil else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            break                       // still on screen, waiting for an answer
        case .denied, .restricted:
            finish(nil)
        default:
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        finish(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}

// MARK: - The transit engine

/// Owns the arrivals shown on the home card and the transit screen.
///
/// Every successful fetch is written to kalla.json, and the last one is read
/// back at launch, so a failed refresh can show real arrivals with an honest
/// timestamp instead of a spinner or a dash.
@Observable
final class Transit {
    private(set) var stop: TransitStop?
    private(set) var arrivals: [TransitArrival] = []
    private(set) var alerts: [TransitAlert] = []
    private(set) var fetchedAt: Date?

    /// Showing the home stop because location was refused or unavailable.
    private(set) var usedFallback = false

    /// The last refresh failed and everything on screen is from the one
    /// before it. Not an error state: the screen stays useful.
    private(set) var isStale = false

    private(set) var isLoading = false

    private let finder = LocationFinder()

    init() {
        let cached = Store.document.transit
        stop = cached.stop
        arrivals = cached.arrivals
        alerts = cached.alerts
        fetchedAt = cached.fetchedAt
        usedFallback = cached.usedFallback
        isStale = cached.fetchedAt != nil
    }

    // MARK: Reading

    /// Arrivals still in the future. A cached set goes out of date just by
    /// sitting there, and a bus that has already gone is worse than nothing.
    var upcoming: [TransitArrival] {
        let now = Date()
        return arrivals.filter { $0.time > now }
    }

    var next: TransitArrival? { upcoming.first }

    /// The two directions, each with where that way ends up, soonest first.
    var byDirection: [(direction: String, arrivals: [TransitArrival])] {
        Dictionary(grouping: upcoming, by: \.directionID)
            .sorted { $0.key < $1.key }
            .map { (($0.value.first?.direction ?? "—"), $0.value) }
    }

    // MARK: Refreshing

    /// Used by the transit screen. Asks where you are, which is the only
    /// place in the app that does.
    func locate() async {
        await load(locating: true)
    }

    /// Used by the home card. Re-reads the stop already resolved, so the card
    /// stays live without the app ever asking for location on its own.
    func refreshKnownStop() async {
        await load(locating: false)
    }

    private func load(locating: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var fellBack = false
        var target = stop

        if locating {
            if let here = await finder.coordinate() {
                // A move of a few streets changes the answer, so the nearest
                // stop is resolved fresh every time the screen opens.
                let found = try? await MBTA.nearestStop(to: here.latitude, here.longitude)
                if let found {
                    finish(stop: found.stop, arrivals: found.arrivals, fallback: false)
                    return
                }
            } else {
                fellBack = true
            }
        }

        if target == nil {
            // Never resolved a stop, so the home stop is the best guess and
            // the screen says as much.
            target = .fallback
            fellBack = true
        }
        guard let target else { return }

        do {
            let found = try await MBTA.arrivals(at: target.id)
            finish(stop: target, arrivals: found, fallback: fellBack || usedFallback)
        } catch {
            // Keep whatever is already on screen and mark it as old.
            isStale = true
            if fellBack { usedFallback = true }
        }
    }

    private func finish(stop: TransitStop, arrivals: [TransitArrival], fallback: Bool) {
        self.stop = stop
        self.arrivals = arrivals
        self.usedFallback = fallback
        self.fetchedAt = Date()
        self.isStale = false

        persist()
        Task { await loadAlerts(for: arrivals) }
    }

    /// Alerts are a second call, so they are fetched after the arrivals are
    /// already on screen rather than holding them up.
    private func loadAlerts(for arrivals: [TransitArrival]) async {
        let routes = Array(Set(arrivals.map(\.route)))
        guard !routes.isEmpty else {
            alerts = []
            persist()
            return
        }

        if let found = try? await MBTA.alerts(routes: routes) {
            alerts = found
            persist()
        }
    }

    private func persist() {
        let snapshot = TransitSnapshot(
            stop: stop, arrivals: arrivals, alerts: alerts,
            fetchedAt: fetchedAt, usedFallback: usedFallback
        )
        Store.mutate { $0.transit = snapshot }
    }
}

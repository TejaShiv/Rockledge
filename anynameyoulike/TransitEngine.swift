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
    /// The nearest stop, or the home stop when location is off. This is what
    /// the home card shows and the only stop that is ever cached.
    private(set) var baseStop: TransitStop?

    /// A stop picked by hand on the transit screen. Deliberately not stored
    /// and not cached: it lasts for one visit and is cleared on the way out.
    private(set) var selectedStop: TransitStop?

    var stop: TransitStop? { selectedStop ?? baseStop }
    var isOnHomeStop: Bool { stop?.id == TransitStop.fallback.id }

    /// Bus stops around you, nearest first, for the picker.
    private(set) var nearbyStops: [TransitStop] = []

    /// What `nearbyStops` is sorted and measured from, so the distances shown
    /// agree with the order rather than being taken from a different point.
    private(set) var origin: TransitPoint?

    /// Live positions for the routes serving the selected stop. Never cached.
    private(set) var vehicles: [TransitVehicle] = []

    private(set) var arrivals: [TransitArrival] = []
    private(set) var alerts: [TransitAlert] = []
    private(set) var fetchedAt: Date?

    private var pollTask: Task<Void, Never>?

    /// Often enough to see a bus move, rarely enough not to cook the battery.
    private let pollEvery: Duration = .seconds(12)

    /// Both sides of a road are separate stops, so a useful list needs room
    /// for pairs. Thirty covers roughly a quarter-mile in Roxbury and every
    /// stop within the search radius somewhere quieter.
    private static let stopsShown = 30

    /// Showing the home stop because location was refused or unavailable.
    private(set) var usedFallback = false

    /// The last refresh failed and everything on screen is from the one
    /// before it. Not an error state: the screen stays useful.
    private(set) var isStale = false

    private(set) var isLoading = false

    private let finder = LocationFinder()

    init() {
        let cached = Store.document.transit
        baseStop = cached.stop
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
    ///
    /// Always goes back to the nearest stop: a stop picked by hand lasts for
    /// one visit, so opening the screen starts from where you actually are.
    func locate() async {
        selectedStop = nil
        await load(locating: true)
    }

    /// Used by the home card. Re-reads the stop already resolved, so the card
    /// stays live without the app ever asking for location on its own.
    func refreshKnownStop() async {
        selectedStop = nil
        await load(locating: false)
    }

    private func load(locating: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var fellBack = false
        var target = baseStop

        if locating {
            if let here = await finder.coordinate() {
                // A move of a few streets changes the answer, so the nearest
                // stop is resolved fresh every time the screen opens.
                async let nearby = try? MBTA.stops(near: here.latitude, here.longitude)
                let found = try? await MBTA.nearestStop(to: here.latitude, here.longitude)
                nearbyStops = await nearby ?? []
                origin = TransitPoint(latitude: here.latitude, longitude: here.longitude)
                sortNearby()

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

        // With no location there is no "near you", so the picker lists what is
        // around the stop being shown instead. The banner says why.
        if nearbyStops.isEmpty {
            nearbyStops = (try? await MBTA.stops(near: target.latitude, target.longitude)) ?? []
            origin = TransitPoint(latitude: target.latitude, longitude: target.longitude)
            sortNearby()
        }

        do {
            let found = try await MBTA.arrivals(at: target.id)
            finish(stop: target, arrivals: found, fallback: fellBack || usedFallback)
        } catch {
            // Keep whatever is already on screen and mark it as old.
            isStale = true
            if fellBack { usedFallback = true }
        }
    }

    /// The API sorts by its own distance metric, which disagrees with ours by
    /// a metre or two and puts the list out of order against the numbers shown
    /// beside it. Sorting by what is displayed keeps the two honest.
    private func sortNearby() {
        guard let origin else { return }
        nearbyStops.sort {
            MBTA.distance(origin.latitude, origin.longitude, $0.latitude, $0.longitude)
                < MBTA.distance(origin.latitude, origin.longitude, $1.latitude, $1.longitude)
        }
        // Cut the list down only after it is in order, so the cap drops the
        // furthest stops rather than whichever ones the server ranked last.
        nearbyStops = Array(nearbyStops.prefix(Self.stopsShown))
    }

    // MARK: Picking a stop

    /// Shows a stop chosen by hand. Nothing here is cached, so leaving the
    /// screen and coming back lands on the nearest stop again.
    func select(_ stop: TransitStop) async {
        guard stop.id != self.stop?.id else { return }

        selectedStop = stop
        vehicles = []

        do {
            let found = try await MBTA.arrivals(at: stop.id)
            arrivals = found
            fetchedAt = Date()
            isStale = false
            await loadAlerts(for: found)
            await loadVehicles()
        } catch {
            isStale = true
        }
    }

    /// The star in the header: straight to the home stop from anywhere.
    func selectHomeStop() async {
        await select(.fallback)
    }

    private func finish(stop: TransitStop, arrivals: [TransitArrival], fallback: Bool) {
        self.baseStop = stop
        self.arrivals = arrivals
        self.usedFallback = fallback
        self.fetchedAt = Date()
        self.isStale = false

        // Only the nearest stop is cached. A hand-picked one must not become
        // what the home card shows next launch.
        persist()
        Task {
            await loadAlerts(for: arrivals)
            await loadVehicles()
        }
    }

    // MARK: Live buses

    /// Polled rather than streamed, and only while the screen is up.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadVehicles()
                guard let every = self?.pollEvery else { return }
                try? await Task.sleep(for: every)
            }
        }
    }

    /// Called when the screen goes away or the app leaves the foreground.
    /// Nothing keeps running in the background.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func loadVehicles() async {
        let routes = Array(Set(upcoming.map(\.route)))
        guard !routes.isEmpty else {
            vehicles = []
            return
        }

        if let found = try? await MBTA.vehicles(routes: routes, matching: arrivals) {
            // A jump every twelve seconds is honest about what is known; an
            // interpolated glide would be inventing positions.
            vehicles = found
        }
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

    /// Writes the nearest stop only. A stop picked by hand is never cached,
    /// so it cannot leak into the home card or survive a relaunch.
    private func persist() {
        guard selectedStop == nil, let baseStop else { return }

        let snapshot = TransitSnapshot(
            stop: baseStop, arrivals: arrivals, alerts: alerts,
            fetchedAt: fetchedAt, usedFallback: usedFallback
        )
        Store.mutate { $0.transit = snapshot }
    }
}

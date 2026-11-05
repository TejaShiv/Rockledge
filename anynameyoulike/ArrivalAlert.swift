import CoreLocation
import Foundation
import Observation
import UserNotifications

// MARK: - What is being watched for

/// Kept in the document rather than in memory, because the whole point is to
/// survive being killed: iOS suspends and then terminates the app, and the
/// alert has to still be there when a region crossing wakes it hours later.
nonisolated struct ArrivalWatch: Codable, Equatable {
    var stopID: String
    var name: String
    var latitude: Double
    var longitude: Double
    var armedAt: Date
}

// MARK: - The alert

/// Wakes you when you get near a stop, with the phone locked and the app
/// closed.
///
/// Region monitoring rather than a timer or repeated location reads: iOS
/// suspends the app in the background, which stops a timer dead and makes
/// polling both unreliable and expensive. A monitored region is held by the
/// system, costs nothing while you are nowhere near it, and launches the app
/// to deliver the alert.
@Observable
final class ArrivalAlert: NSObject, CLLocationManagerDelegate {

    /// Half a mile. Far enough to stand up and get to the door.
    nonisolated static let radius: CLLocationDistance = 804.672

    nonisolated static let regionID = "tally.arrival"
    nonisolated static let category = "arrivalArmed"
    nonisolated static let cancelAction = "cancelArrival"

    nonisolated private static let armedNotice = "arrivalArmed"
    nonisolated private static let arrivedNotice = "arrivalReached"

    private let manager = CLLocationManager()

    private(set) var watch: ArrivalWatch?
    /// Something to say on screen: already there, location refused, and so on.
    private(set) var note: String?
    private(set) var isArming = false

    /// The stop waiting on an authorisation prompt or a location fix.
    private var pending: TransitStop?

    var isArmed: Bool { watch != nil }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        watch = Store.document.arrivalWatch

        // A region crossing can launch the app straight into the background,
        // so whatever was armed is laid down again on every single start.
        if let watch { monitor(watch) }
    }

    // MARK: Arming

    func arm(_ stop: TransitStop) {
        note = nil
        pending = stop

        switch manager.authorizationStatus {
        case .notDetermined:
            // When-in-use first; iOS will not show the always prompt until
            // it has been granted at least that much.
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            // Armed regardless: monitoring works while the app is in use, so
            // a refused upgrade means a narrower alert, not a broken one.
            checkWhetherAlreadyThere()
        case .authorizedAlways:
            checkWhetherAlreadyThere()
        default:
            pending = nil
            note = "Location is off for Tally. Turn it on in Settings to be alerted."
        }
    }

    /// Region monitoring only fires on *crossing* the boundary, so arming
    /// while already inside it would wait for you to leave and come back.
    private func checkWhetherAlreadyThere() {
        guard pending != nil else { return }
        isArming = true
        manager.requestLocation()
    }

    private func commit(_ stop: TransitStop) {
        let armed = ArrivalWatch(
            stopID: stop.id,
            name: stop.name,
            latitude: stop.latitude,
            longitude: stop.longitude,
            armedAt: Date()
        )

        watch = armed
        Store.mutate { $0.arrivalWatch = armed }
        monitor(armed)

        Task { await postArmedNotice(armed) }
    }

    private func monitor(_ armed: ArrivalWatch) {
        // iOS keeps at most twenty regions per app and silently ignores
        // anything past that, so everything previous goes first. There is
        // only ever one of these.
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(
                latitude: armed.latitude, longitude: armed.longitude
            ),
            radius: min(Self.radius, manager.maximumRegionMonitoringDistance),
            identifier: Self.regionID
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false

        manager.startMonitoring(for: region)
    }

    // MARK: Disarming

    func cancel() {
        disarm()
        note = nil
    }

    private func disarm() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }

        watch = nil
        pending = nil
        isArming = false
        Store.mutate { $0.arrivalWatch = nil }

        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [Self.armedNotice])
    }

    // MARK: Location

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard pending != nil else { return }

            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                checkWhetherAlreadyThere()
            case .denied, .restricted:
                pending = nil
                isArming = false
                note = "Location is off for Tally. Turn it on in Settings to be alerted."
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let here = locations.last, let stop = pending else { return }
            isArming = false
            pending = nil

            let away = MBTA.distance(
                here.coordinate.latitude, here.coordinate.longitude,
                stop.latitude, stop.longitude
            )

            guard away > Self.radius else {
                // Arming here would wait for you to leave and come back.
                note = "You are already within half a mile of \(stop.name)."
                return
            }

            commit(stop)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            guard let stop = pending else { return }
            isArming = false
            pending = nil

            // No fix, so whether you are already inside is unknown. Arming is
            // the better guess: the alert may be redundant, where not arming
            // would mean missing the stop.
            commit(stop)
            note = "Could not check where you are, so the alert is set anyway."
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didEnterRegion region: CLRegion) {
        Task { @MainActor in
            guard region.identifier == Self.regionID, let armed = watch else { return }

            await announce(armed)
            // Immediately, so it cannot fire twice on a wobbly boundary.
            disarm()
        }
    }

    // MARK: Saying so

    private func announce(_ armed: ArrivalWatch) async {
        let content = UNMutableNotificationContent()
        content.title = "Nearly at \(armed.name)"
        content.body = "About half a mile out."
        content.sound = .default
        // Breaks through a locked screen and a Focus, which is the entire
        // point of the feature.
        content.interruptionLevel = .timeSensitive

        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: Self.arrivedNotice, content: content, trigger: nil
            )
        )
    }

    /// A quiet, undismissed notice while the alert is set, carrying a cancel
    /// button — so it can be called off from the lock screen without opening
    /// the app.
    private func postArmedNotice(_ armed: ArrivalWatch) async {
        let content = UNMutableNotificationContent()
        content.title = "Alert set for \(armed.name)"
        content.body = "You will be woken about half a mile out. Swipe for Cancel."
        content.categoryIdentifier = Self.category
        content.interruptionLevel = .passive        // no sound, no buzz

        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: Self.armedNotice, content: content, trigger: nil
            )
        )
    }

    /// Registered at launch so the cancel button exists on the notification.
    nonisolated static var notificationCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(
                    identifier: cancelAction,
                    title: "Cancel alert",
                    options: [.destructive]
                )
            ],
            intentIdentifiers: [],
            options: []
        )
    }
}

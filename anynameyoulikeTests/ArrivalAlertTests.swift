import UserNotifications
import CoreLocation
import Foundation
import Testing
@testable import anynameyoulike

/// The arrival alert's arithmetic and its persistence.
///
/// Region monitoring itself cannot be exercised here — it needs a real
/// device crossing a real boundary — so what is covered is everything the
/// decisions rest on: the radius, the already-inside test, and the document
/// round trip that has to survive the app being killed.
struct ArrivalAlertTests {

    /// Half a mile, which is what the radius is specified as.
    @Test func theRadiusIsHalfAMile() {
        let metresPerMile = 1609.344

        #expect(abs(ArrivalAlert.radius - metresPerMile / 2) < 0.01)
        // Comfortably inside what iOS will monitor, which is a couple of
        // hundred kilometres, and well above its ~100m practical floor.
        #expect(ArrivalAlert.radius > 100)
    }

    /// The home stop, and a point a known distance from it.
    private let stop = (lat: 42.3307320, lon: -71.0884200)

    private func away(_ metres: Double) -> (lat: Double, lon: Double) {
        // Due north, so latitude alone moves.
        (lat: stop.lat + metres / 111_320.0, lon: stop.lon)
    }

    /// The test the alert makes at arm time, to catch the case where you are
    /// already inside the region — which never fires, because a region
    /// reports crossings, not occupancy.
    @Test func knowsWhenYouAreAlreadyInside() {
        func inside(_ metres: Double) -> Bool {
            let here = away(metres)
            return MBTA.distance(here.lat, here.lon, stop.lat, stop.lon)
                <= ArrivalAlert.radius
        }

        #expect(inside(0))
        #expect(inside(400))
        #expect(inside(800))
        #expect(!inside(805))
        #expect(!inside(2000))
    }

    /// A half-mile region around a stop must not already contain the stop
    /// one along — or arming for one would fire at the other.
    @Test func halfAMileIsWiderThanTheGapBetweenStops() {
        // Malcolm X Blvd @ O'Bryant HS to @ Shawmut Ave, from the API.
        let neighbour = (lat: 42.3296870, lon: -71.0861300)
        let gap = MBTA.distance(stop.lat, stop.lon, neighbour.lat, neighbour.lon)

        #expect(gap < ArrivalAlert.radius)
        // Not a defect — it is why the alert names the stop it was set for
        // rather than claiming you have arrived.
        #expect(gap > 100)
    }

    // MARK: Surviving being killed

    @Test func theArmedStopRoundTripsThroughTheDocument() throws {
        let armed = ArrivalWatch(
            stopID: "11149",
            name: "Malcolm X Blvd @ O'Bryant HS",
            latitude: stop.lat,
            longitude: stop.lon,
            armedAt: Date(timeIntervalSince1970: 1_793_000_000)
        )

        var document = Store.Document()
        document.arrivalWatch = armed

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(
            Store.Document.self, from: try encoder.encode(document)
        )

        #expect(back.arrivalWatch == armed)
    }

    /// A document written before this feature existed still opens, with
    /// nothing armed.
    @Test func anOlderDocumentOpensWithNothingArmed() throws {
        let json = #"{"version": 1, "groceryItems": [], "useLog": []}"#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(Store.Document.self, from: Data(json.utf8))

        #expect(document.arrivalWatch == nil)
    }

    // MARK: The cancel button on the notification

    @Test func theNotificationCarriesACancelAction() {
        let category = ArrivalAlert.notificationCategory

        #expect(category.identifier == ArrivalAlert.category)
        #expect(category.actions.count == 1)
        #expect(category.actions.first?.identifier == ArrivalAlert.cancelAction)
        #expect(category.actions.first?.title == "Cancel alert")
    }
}

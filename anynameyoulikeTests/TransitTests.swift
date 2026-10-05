import Foundation
import Testing
@testable import anynameyoulike

/// The nearest-stop maths, which runs on every open of the transit screen and
/// decides which stop you are shown. No network: these are the pure parts.
struct TransitTests {

    // Real coordinates around the home stop, so the numbers mean something.
    private let home = TransitStop.fallback                       // 11149
    private let opposite = TransitStop(                           // 11323, across the road
        id: "11323", name: "Malcolm X Blvd opp O'Bryant HS",
        latitude: 42.330801, longitude: -71.089207
    )
    private let madison = TransitStop(                            // ~200m up the road
        id: "11148", name: "Malcolm X Blvd @ Madison Park HS",
        latitude: 42.33129, longitude: -71.09112
    )

    private func stop(_ id: String, _ lat: Double, _ lon: Double) -> TransitStop {
        TransitStop(id: id, name: id, latitude: lat, longitude: lon)
    }

    private func arrival(_ id: String, minutes: Double) -> TransitArrival {
        TransitArrival(
            id: id, route: "28", headsign: "Ruggles", direction: "Ruggles Station",
            directionID: 1, time: Date().addingTimeInterval(minutes * 60)
        )
    }

    // MARK: Distance

    @Test func distanceToItselfIsZero() {
        #expect(MBTA.distance(home.latitude, home.longitude,
                              home.latitude, home.longitude) == 0)
    }

    /// The two sides of Malcolm X Blvd are about 65 metres apart, which is
    /// what the stop list shows for them.
    @Test func measuresAcrossTheRoad() {
        let away = MBTA.distance(home.latitude, home.longitude,
                                 opposite.latitude, opposite.longitude)
        #expect(away > 50 && away < 90)
    }

    @Test func measuresUpTheRoad() {
        let away = MBTA.distance(home.latitude, home.longitude,
                                 madison.latitude, madison.longitude)
        #expect(away > 180 && away < 260)
    }

    /// A degree of longitude is shorter than a degree of latitude, and at
    /// Boston's latitude it is about three quarters as long.
    @Test func narrowsLongitudeTowardsThePole() {
        let northSouth = MBTA.distance(42.33, -71.09, 42.34, -71.09)
        let eastWest = MBTA.distance(42.33, -71.09, 42.33, -71.08)

        #expect(northSouth > eastWest)
        #expect(eastWest / northSouth > 0.70)
        #expect(eastWest / northSouth < 0.78)
    }

    @Test func isSymmetric() {
        let there = MBTA.distance(42.330, -71.090, 42.336, -71.084)
        let back = MBTA.distance(42.336, -71.084, 42.330, -71.090)
        #expect(abs(there - back) < 0.0001)
    }

    // MARK: Which stops count as equally near

    @Test func aClearWinnerIsTheOnlyOneTied() {
        let tied = MBTA.tiedForNearest(
            [home, opposite, madison], to: home.latitude, home.longitude
        )

        #expect(tied.count == 1)
        #expect(tied.first?.id == home.id)
    }

    /// Two stops within a few metres of each other both count, so the tie can
    /// be settled on which has a bus coming sooner.
    @Test func stopsWithinAFewMetresAreAllTied() {
        let a = stop("a", 42.330732, -71.088420)
        let b = stop("b", 42.330760, -71.088440)   // ~3m away
        let far = madison

        let tied = MBTA.tiedForNearest([far, a, b], to: a.latitude, a.longitude)

        #expect(tied.count == 2)
        #expect(Set(tied.map(\.id)) == ["a", "b"])
    }

    @Test func tiesAreOrderedNearestFirst() {
        let a = stop("a", 42.330732, -71.088420)
        let b = stop("b", 42.330740, -71.088430)
        let c = stop("c", 42.330755, -71.088445)

        // Handed over in the wrong order on purpose.
        let tied = MBTA.tiedForNearest([c, b, a], to: a.latitude, a.longitude)

        #expect(tied.map(\.id) == ["a", "b", "c"])
    }

    /// The nearest is worked out from the whole list, not from whichever stop
    /// the server happened to put first.
    @Test func doesNotTrustTheOrderItWasGiven() {
        let near = stop("near", 42.330732, -71.088420)
        let far = stop("far", 42.340000, -71.100000)

        let tied = MBTA.tiedForNearest([far, near], to: near.latitude, near.longitude)

        #expect(tied.first?.id == "near")
        #expect(tied.count == 1)
    }

    @Test func capsHowManyStopsAreCheckedForATie() {
        let crowd = (0..<10).map { stop("s\($0)", 42.330732 + Double($0) * 0.00001, -71.088420) }

        let tied = MBTA.tiedForNearest(crowd, to: 42.330732, -71.088420, limit: 4)

        #expect(tied.count == 4)
    }

    @Test func noStopsMeansNoTie() {
        #expect(MBTA.tiedForNearest([], to: 42.33, -71.09).isEmpty)
    }

    // MARK: Breaking the tie on the soonest bus

    @Test func picksTheStopWithTheSoonestBus() {
        let chosen = MBTA.soonest(among: [
            (home, [arrival("later", minutes: 9)]),
            (opposite, [arrival("sooner", minutes: 2)]),
        ])

        #expect(chosen?.stop.id == opposite.id)
    }

    /// Arrivals are sorted on the way in, but the tie-break must not fall over
    /// if they ever are not.
    @Test func looksAtEveryArrivalNotJustTheFirst() {
        let chosen = MBTA.soonest(among: [
            (home, [arrival("a", minutes: 8), arrival("b", minutes: 1)]),
            (opposite, [arrival("c", minutes: 4)]),
        ])

        #expect(chosen?.stop.id == home.id)
    }

    @Test func aStopWithNothingPredictedLosesToOneWithABus() {
        let chosen = MBTA.soonest(among: [
            (home, []),
            (opposite, [arrival("only", minutes: 20)]),
        ])

        #expect(chosen?.stop.id == opposite.id)
    }

    @Test func nothingPredictedAnywhereHasNoWinner() {
        #expect(MBTA.soonest(among: [(home, []), (opposite, [])]) == nil)
        #expect(MBTA.soonest(among: []) == nil)
    }

    @Test func carriesTheArrivalsOfTheStopItPicked() {
        let theirs = [arrival("x", minutes: 3), arrival("y", minutes: 11)]

        let chosen = MBTA.soonest(among: [
            (home, [arrival("late", minutes: 30)]),
            (opposite, theirs),
        ])

        #expect(chosen?.arrivals.map(\.id) == ["x", "y"])
    }

    // MARK: Search settings

    /// A page limit below the number of stops in range is what hides them, so
    /// the fetch takes the server's ceiling and the trimming happens after
    /// sorting. Roxbury has 92 bus stops within this radius.
    @Test func searchesWideEnoughForADenseArea() {
        #expect(MBTA.searchRadius >= 0.01)
        #expect(MBTA.tieMetres > 0 && MBTA.tieMetres < 50)
    }
}

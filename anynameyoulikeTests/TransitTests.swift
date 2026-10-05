import Foundation
import Testing
@testable import anynameyoulike

/// The nearest-stop maths, which runs on every open of the transit screen and
/// decides which stop you are shown. No network: these are the pure parts.
struct TransitTests {

    // Real coordinates around the home stop, so the numbers mean something.
    // This is 11149 itself, not TransitStop.fallback: the fallback is the
    // paired stop and sits midway between the two sides.
    private let home = TransitStop(
        id: "11149", name: "Malcolm X Blvd @ O'Bryant HS",
        latitude: 42.330732, longitude: -71.08842
    )
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

    // MARK: Pairing the two sides of a road

    /// The real pair on Malcolm X Blvd, as the API returns them.
    private var obryantSides: [TransitStop] {
        [
            stop("11149", 42.330732, -71.088420),
            stop("11323", 42.330801, -71.089207),
        ].enumerated().map { index, s in
            var named = s
            named.name = index == 0
                ? "Malcolm X Blvd @ O'Bryant HS"
                : "Malcolm X Blvd opp O'Bryant HS"
            return named
        }
    }

    @Test func foldsTwoSidesOfARoadIntoOneStop() {
        let merged = MBTA.paired(obryantSides)

        #expect(merged.count == 1)
        #expect(merged.first?.id == "11149")
        #expect(merged.first?.pairedWith == "11323")
        #expect(merged.first?.isPaired == true)
    }

    @Test func aPairedStopAsksAboutBothIds() {
        let merged = MBTA.paired(obryantSides).first

        #expect(merged?.queryIDs == ["11149", "11323"])
    }

    @Test func anUnpairedStopAsksAboutItselfOnly() {
        let lone = stop("999", 42.33, -71.09)

        #expect(MBTA.paired([lone]).first?.queryIDs == ["999"])
        #expect(MBTA.paired([lone]).first?.isPaired == false)
    }

    /// The "@" side names the pair: "opp" only says which one it is not.
    @Test func thePairTakesTheNameOfTheNearSide() {
        let merged = MBTA.paired(obryantSides.reversed())

        #expect(merged.first?.name == "Malcolm X Blvd @ O'Bryant HS")
        #expect(merged.first?.id == "11149")
    }

    @Test func thePairSitsBetweenItsTwoSides() {
        let merged = MBTA.paired(obryantSides).first

        #expect(merged?.latitude == (42.330732 + 42.330801) / 2)
        #expect(merged?.longitude == (-71.088420 + -71.089207) / 2)
    }

    /// Two stops really can share a name and be nowhere near each other —
    /// there are two "Tremont St @ Columbus Ave" 840m apart.
    @Test func doesNotPairTheSameNameFarApart() {
        var near = stop("a", 42.330, -71.090); near.name = "Tremont St @ Columbus Ave"
        var far = stop("b", 42.3376, -71.090); far.name = "Tremont St @ Columbus Ave"

        let merged = MBTA.paired([near, far])

        #expect(merged.count == 2)
        #expect(merged.allSatisfy { !$0.isPaired })
    }

    /// Ten stops are called "Ruggles". That is a station, not a pair, and
    /// picking two of them would be arbitrary.
    @Test func leavesGroupsBiggerThanAPairAlone() {
        let berths = (0..<10).map { index -> TransitStop in
            var s = stop("r\(index)", 42.3362 + Double(index) * 0.00005, -71.0892)
            s.name = "Ruggles"
            return s
        }

        let merged = MBTA.paired(berths)

        #expect(merged.count == 10)
        #expect(merged.allSatisfy { !$0.isPaired })
    }

    @Test func pairingKeyIgnoresWhichSideOfTheRoad() {
        #expect(MBTA.pairingKey("Malcolm X Blvd @ O'Bryant HS")
                == MBTA.pairingKey("Malcolm X Blvd opp O'Bryant HS"))
        #expect(MBTA.pairingKey("Centre St @ Cedar St")
                == MBTA.pairingKey("Centre St  OPP  Cedar St"))
        #expect(MBTA.pairingKey("Washington St @ Cedar St")
                != MBTA.pairingKey("Washington St @ Ruggles St"))
    }

    @Test func theHomeStopShipsAlreadyPaired() {
        #expect(TransitStop.fallback.isPaired)
        #expect(TransitStop.fallback.queryIDs == ["11149", "11323"])
    }

    @Test func pairingKeepsEveryStopItWasGiven() {
        let all = obryantSides + [stop("x", 42.34, -71.10), stop("y", 42.35, -71.11)]

        let merged = MBTA.paired(all)
        let covered = merged.flatMap(\.queryIDs)

        #expect(Set(covered) == Set(all.map(\.id)))
    }
}

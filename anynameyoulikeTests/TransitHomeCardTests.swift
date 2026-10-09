import Foundation
import Testing
@testable import anynameyoulike

/// What the home card chooses to show.
///
/// Serialised: these write the home slice of the one shared document, so
/// siblings running at the same time would be reading each other's arrivals.
@Suite(.serialized)
struct TransitHomeCardTests {

    // MARK: What the home card picks

    /// The card's choice is pure given a set of arrivals, so it is exercised
    /// through a Transit built from a document rather than the network.
    private func arrival(route: String, to destination: String,
                         minutes: Double) -> TransitArrival {
        // A second of slack: minutes() floors, and the clock moves between
        // building this and reading it back, which would otherwise shave a
        // whole minute off every expectation.
        TransitArrival(
            id: "\(route)-\(destination)-\(minutes)",
            route: route, headsign: destination, direction: destination,
            directionID: 1, time: Date().addingTimeInterval(minutes * 60 + 1)
        )
    }

    /// Asks the selection logic directly.
    ///
    /// Deliberately not through Store: these tests run inside the app, which
    /// fetches real arrivals into the same slice while they run, and a live
    /// 23 towards Ruggles turned up in the middle of one.
    private func homeLines(given arrivals: [TransitArrival]) -> [TransitArrival] {
        Transit.homeLines(from: arrivals)
    }

    @Test func showsTheNext23AndThe28() {
        let lines = homeLines(given: [
            arrival(route: "28", to: "Ruggles", minutes: 9),
            arrival(route: "23", to: "Ruggles", minutes: 4),
            arrival(route: "23", to: "Ruggles", minutes: 22),   // later 23
            arrival(route: "66", to: "Nubian via Allston", minutes: 2),
        ])

        #expect(lines.count == 2)
        #expect(lines.map(\.route) == ["23", "28"])      // soonest first
        #expect(lines.map { $0.minutes() } == [4, 9])    // the next of each
    }

    @Test func showsJustTheOneRouteThatIsRunning() {
        let lines = homeLines(given: [
            arrival(route: "28", to: "Ruggles", minutes: 6),
            arrival(route: "66", to: "Nubian via Allston", minutes: 1),
        ])

        #expect(lines.map(\.route) == ["28"])
    }

    /// With neither of them due, anything heading the same way is better than
    /// an empty card.
    @Test func fallsBackToAnyRouteTowardsRuggles() {
        let lines = homeLines(given: [
            arrival(route: "45", to: "Ruggles", minutes: 11),
            arrival(route: "15", to: "Ruggles", minutes: 5),
            arrival(route: "66", to: "Nubian via Allston", minutes: 1),
        ])

        #expect(lines.map(\.route) == ["15", "45"])
    }

    @Test func ignoresBusesGoingTheOtherWay() {
        let lines = homeLines(given: [
            arrival(route: "66", to: "Nubian via Allston", minutes: 2),
            arrival(route: "23", to: "Ashmont", minutes: 3),
            arrival(route: "28", to: "Mattapan", minutes: 4),
        ])

        #expect(lines.isEmpty)
    }

    @Test func ignoresBusesThatHaveAlreadyGone() {
        let lines = homeLines(given: [
            arrival(route: "23", to: "Ruggles", minutes: -5),
            arrival(route: "28", to: "Ruggles", minutes: 7),
        ])

        #expect(lines.map(\.route) == ["28"])
    }

    @Test func nothingDueGivesNothingToShow() {
        #expect(homeLines(given: []).isEmpty)
    }

    @Test func neverShowsMoreThanTwoLines() {
        let lines = homeLines(given: (1...6).map {
            arrival(route: "4\($0)", to: "Ruggles", minutes: Double($0))
        })

        #expect(lines.count == 2)
    }

    /// A cold launch has the last known times on screen immediately, marked
    /// as old, rather than an empty card waiting on the network.
    @Test func aColdLaunchRestoresTheLastTimesAsStale() {
        let before = Store.document.transitHome
        defer { Store.mutate { $0.transitHome = before } }

        let fetched = Date().addingTimeInterval(-600)
        Store.mutate {
            $0.transitHome = TransitSnapshot(
                stop: .fallback,
                arrivals: [arrival(route: "23", to: "Ruggles", minutes: 7)],
                alerts: [], fetchedAt: fetched, usedFallback: false
            )
        }

        let engine = Transit()

        #expect(engine.homeIsStale)
        #expect(engine.homeFetchedAt == fetched)
        #expect(Transit.homeLines(from: engine.homeArrivals).map(\.route) == ["23"])
    }

    @Test func aFirstEverLaunchHasNothingToMarkStale() {
        let before = Store.document.transitHome
        defer { Store.mutate { $0.transitHome = before } }

        Store.mutate { $0.transitHome = TransitSnapshot() }
        let engine = Transit()

        #expect(!engine.homeIsStale)
        #expect(engine.homeLines.isEmpty)
    }

    @Test func theCardIsPinnedToTheHomeStop() {
        // Whatever the dashboard last resolved lives in a different slice.
        #expect(TransitStop.fallback.queryIDs == ["11149", "11323"])
    }
}

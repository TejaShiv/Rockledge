import Foundation
import Testing
@testable import anynameyoulike

/// Finding a stop by name.
///
/// The V3 API rejects `filter[name]` outright, so the whole list is held
/// locally and searched here. These run against a hand-built list rather
/// than the real 7,600, so nothing touches the network.
struct StopSearchTests {

    private func stop(_ id: String, _ name: String,
                      _ lat: Double = 42.33, _ lon: Double = -71.08) -> TransitStop {
        TransitStop(id: id, name: name, latitude: lat, longitude: lon)
    }

    /// Names taken from the real API, including the awkward ones.
    private var stops: [TransitStop] {
        [
            stop("1", "Ruggles", 42.3362, -71.0892),
            stop("2", "Washington St @ Ruggles St", 42.3345, -71.0810),
            stop("3", "Ruggles St @ Huntington Ave", 42.3371, -71.0920),
            stop("4", "Malcolm X Blvd @ O'Bryant HS", 42.3307, -71.0884),
            stop("5", "Malcolm X Blvd opp O'Bryant HS", 42.3308, -71.0892),
            stop("6", "Columbus Ave @ Malcolm X Blvd", 42.3290, -71.0860),
            stop("7", "Nubian", 42.3290, -71.0830),
        ]
    }

    private func find(_ text: String, near origin: TransitPoint? = nil) -> [String] {
        StopDirectory.search(text, in: stops, near: origin).map(\.name)
    }

    // MARK: Ranking

    /// "Ruggles" turns up twenty-nine stops on the real system. The one
    /// actually called Ruggles has to come first, not the twelfth
    /// "Washington St @ Ruggles St".
    @Test func theExactNameWins() {
        #expect(find("ruggles").first == "Ruggles")
    }

    @Test func aPrefixBeatsAMatchInTheMiddle() {
        let hits = find("ruggles st")

        #expect(hits.first == "Ruggles St @ Huntington Ave")
        #expect(hits.contains("Washington St @ Ruggles St"))
    }

    /// Every word has to appear, but not in order and not together — nobody
    /// remembers where the "@" goes.
    @Test func matchesWordsInAnyOrder() {
        #expect(find("obryant malcolm").count == 2)
        #expect(find("malcolm columbus") == ["Columbus Ave @ Malcolm X Blvd"])
    }

    @Test func ignoresCaseAndSurroundingSpace() {
        #expect(find("  NUBIAN  ") == ["Nubian"])
    }

    /// Apostrophes and "@" are in the official names and in nobody's typing.
    @Test func ignoresPunctuationNobodyTypes() {
        #expect(find("obryant").count == 2)
        #expect(find("o'bryant").count == 2)
        // Both sides of the road carry all four words, so both match — and
        // the one whose name actually starts that way comes first.
        #expect(find("malcolm x blvd obryant").first == "Malcolm X Blvd @ O'Bryant HS")
    }

    // MARK: Not searching

    /// One letter matches half the system, so it waits for two.
    @Test func staysQuietUntilThereIsSomethingToGoOn() {
        #expect(find("").isEmpty)
        #expect(find("r").isEmpty)
        #expect(find("ru").isEmpty == false)
    }

    @Test func saysNothingRatherThanGuessing() {
        #expect(find("alewife").isEmpty)
    }

    // MARK: Distance as a tiebreak

    /// Two stops of the same rank: the nearer one first.
    @Test func prefersTheNearerOfEqualMatches() {
        let nearOBryant = TransitPoint(latitude: 42.3307, longitude: -71.0884)

        let hits = StopDirectory.search(
            "o'bryant", in: stops, near: nearOBryant
        )

        #expect(hits.first?.name == "Malcolm X Blvd @ O'Bryant HS")
        #expect(hits.count == 2)
    }

    /// Without a location it still answers, just without that tiebreak.
    @Test func worksWithNoLocationAtAll() {
        #expect(find("o'bryant").count == 2)
    }

    // MARK: The cap

    @Test func neverReturnsMoreThanAskedFor() {
        let many = (0..<100).map { stop("\($0)", "Washington St \($0)") }

        #expect(StopDirectory.search("washington", in: many, limit: 25).count == 25)
        #expect(StopDirectory.search("washington", in: many, limit: 5).count == 5)
    }
}

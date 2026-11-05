import Foundation
import Observation

// MARK: - Every stop on the system

/// The whole stop list, kept on disk so a stop can be found by name rather
/// than only by being near it.
///
/// The V3 API has no name filter — `filter[name]` is rejected outright — so
/// searching means holding the list locally. It is about 7,600 stops and
/// 2 MB over the wire, which is a second once a month, and stop names and
/// positions barely move.
///
/// Deliberately not in kalla.json: this is a copy of MBTA's data, not yours,
/// so it has no business in the backup you export.
nonisolated enum StopDirectory {

    /// Stops change rarely enough that a month is generous.
    static let staleAfter: TimeInterval = 30 * 24 * 3600

    struct Cache: Codable {
        var stops: [TransitStop]
        var fetchedAt: Date
    }

    static var url: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: support, withIntermediateDirectories: true
        )
        return support.appendingPathComponent("mbta-stops.json")
    }

    static func read() -> Cache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Cache.self, from: data)
    }

    static func write(_ cache: Cache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Searching

    /// Matches on name, best first.
    ///
    /// Ranked rather than filtered: typing "ruggles" turns up twenty-nine
    /// stops, and "Ruggles" itself has to be the one at the top rather than
    /// the twelfth "Washington St @ Ruggles St".
    /// Lowercased with punctuation taken out, so "o'bryant" and "obryant"
    /// are the same thing. Nobody types that apostrophe, and "St." against
    /// "St" would otherwise miss too.
    static func folded(_ text: String) -> String {
        text.lowercased().unicodeScalars.reduce(into: "") { out, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else if scalar == " " || scalar == "\t" {
                out.append(" ")
            }
            // Everything else — apostrophes, @, periods, slashes — is dropped.
        }
    }

    /// Matches on name, best first.
    ///
    /// Ranked rather than filtered: typing "ruggles" turns up twenty-nine
    /// stops, and "Ruggles" itself has to be the one at the top rather than
    /// the twelfth "Washington St @ Ruggles St".
    static func search(_ text: String,
                       in stops: [TransitStop],
                       near origin: TransitPoint? = nil,
                       limit: Int = 25) -> [TransitStop] {
        let wanted = folded(text).trimmingCharacters(in: .whitespaces)
        guard wanted.count >= 2 else { return [] }

        // Every word has to appear somewhere, so "obryant malcolm" finds the
        // stop without having to remember the order or the "@".
        let words = wanted.split(separator: " ").map(String.init)

        let scored = stops.compactMap { stop -> (TransitStop, Int, Double)? in
            let name = folded(stop.name)
            guard words.allSatisfy({ name.contains($0) }) else { return nil }

            let rank: Int
            if name == wanted { rank = 0 }
            else if name.hasPrefix(wanted) { rank = 1 }
            else if name.contains(wanted) { rank = 2 }
            else { rank = 3 }                       // words matched, scattered

            let away = origin.map {
                MBTA.distance($0.latitude, $0.longitude,
                              stop.latitude, stop.longitude)
            } ?? 0

            return (stop, rank, away)
        }

        return scored
            .sorted {
                // Rank first, then nearer, then shorter — a shorter name is
                // the more general place, which is usually what was meant.
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                if $0.2 != $1.2 { return $0.2 < $1.2 }
                return $0.0.name.count < $1.0.name.count
            }
            .prefix(limit)
            .map(\.0)
    }
}

// MARK: - The screen's copy

/// Holds the stop list and the current search for the UI.
@Observable
final class StopFinder {

    private(set) var stops: [TransitStop] = []
    private(set) var isLoading = false
    private(set) var problem: String?
    private(set) var fetchedAt: Date?

    var query: String = ""

    init() {
        if let cache = StopDirectory.read() {
            stops = cache.stops
            fetchedAt = cache.fetchedAt
        }
    }

    var isStale: Bool {
        guard let fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) > StopDirectory.staleAfter
    }

    func results(near origin: TransitPoint?) -> [TransitStop] {
        StopDirectory.search(query, in: stops, near: origin)
    }

    /// Fetched on first use rather than at launch: most of the time nobody
    /// searches, and two megabytes for a screen you did not open is rude.
    func loadIfNeeded() async {
        guard !isLoading, stops.isEmpty || isStale else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let found = try await MBTA.everyStop()
            guard !found.isEmpty else { return }

            stops = found
            fetchedAt = Date()
            problem = nil
            StopDirectory.write(StopDirectory.Cache(stops: found, fetchedAt: Date()))
        } catch {
            // A stale list still searches, so this only matters on a first run.
            problem = stops.isEmpty ? "Could not load the stop list" : nil
        }
    }
}

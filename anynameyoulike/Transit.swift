import Foundation

// MARK: - Model

/// A bus stop, kept whole so the card can name it without a network call.
nonisolated struct TransitStop: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    /// The home stop, used when location is refused or unavailable.
    static let fallback = TransitStop(
        id: "11149",
        name: "Malcolm X Blvd @ O'Bryant HS",
        latitude: 42.330732,
        longitude: -71.08842
    )
}

/// The point the stop list is measured and sorted from: where you are, or
/// the home stop when location is off.
nonisolated struct TransitPoint: Equatable {
    var latitude: Double
    var longitude: Double
}

nonisolated struct TransitArrival: Codable, Equatable, Identifiable {
    var id: String
    var route: String           // "66"
    var headsign: String        // "Harvard via Allston"
    var direction: String       // "Harvard Square", the end of the line
    var directionID: Int
    var time: Date

    /// Kept so a live vehicle can be matched to the arrival it will become,
    /// and so its distance in stops can be worked out.
    var tripID: String?
    var stopSequence: Int?

    /// Whole minutes away, floored, never negative.
    func minutes(from now: Date = Date()) -> Int {
        max(0, Int(time.timeIntervalSince(now) / 60))
    }
}

/// A bus out on the road right now. Not cached: a position is worthless the
/// moment it is stale, so it is either live or absent.
nonisolated struct TransitVehicle: Equatable, Identifiable {
    var id: String
    var route: String
    var latitude: Double
    var longitude: Double
    var label: String           // the number on the side of the bus
    var status: String          // STOPPED_AT, IN_TRANSIT_TO, INCOMING_AT
    var tripID: String?

    /// How many stops short of you it is, worked out by comparing where the
    /// bus is on its trip with where you are on it. Nil when the two cannot
    /// be matched up, which is most buses on a route you are not waiting for.
    var stopsAway: Int?

    var stopsAwayLabel: String? {
        guard let stopsAway else { return nil }
        switch stopsAway {
        case ..<0: return nil
        case 0: return "here"
        case 1: return "1 stop"
        default: return "\(stopsAway) stops"
        }
    }
}

nonisolated struct TransitAlert: Codable, Equatable, Identifiable {
    var id: String
    var route: String
    var effect: String          // "DETOUR", "SUSPENSION"
    var header: String

    /// "DETOUR" reads badly in a sentence; "detour" does.
    var label: String {
        effect.replacingOccurrences(of: "_", with: " ").lowercased()
    }
}

/// The last thing the network gave us, kept so a failed refresh shows real
/// arrivals with an honest timestamp rather than a spinner or a dash.
nonisolated struct TransitSnapshot: Codable, Equatable {
    var stop: TransitStop?
    var arrivals: [TransitArrival] = []
    var alerts: [TransitAlert] = []
    var fetchedAt: Date?
    var usedFallback = false

    var isEmpty: Bool { stop == nil }

    init() {}

    enum CodingKeys: String, CodingKey {
        case stop, arrivals, alerts, fetchedAt, usedFallback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }

        stop = (try? c.decodeIfPresent(TransitStop.self, forKey: .stop)) ?? nil
        arrivals = value(.arrivals, [])
        alerts = value(.alerts, [])
        fetchedAt = (try? c.decodeIfPresent(Date.self, forKey: .fetchedAt)) ?? nil
        usedFallback = value(.usedFallback, false)
    }

    init(stop: TransitStop?, arrivals: [TransitArrival], alerts: [TransitAlert],
         fetchedAt: Date?, usedFallback: Bool) {
        self.stop = stop
        self.arrivals = arrivals
        self.alerts = alerts
        self.fetchedAt = fetchedAt
        self.usedFallback = usedFallback
    }
}

// MARK: - The MBTA V3 API

/// Read-only, unauthenticated use of https://api-v3.mbta.com.
///
/// No key is needed. Anonymous callers get 20 requests a minute, which a
/// refresh of two or three calls sits well inside. A free key would raise
/// that to 1000, and is the first thing to add if this ever polls.
nonisolated enum MBTA {
    static let base = "https://api-v3.mbta.com"

    /// Stops closer together than this are treated as the same distance, and
    /// the tie is broken on whichever has a bus coming sooner.
    private static let tieMetres = 15.0

    enum Failure: Error {
        case badResponse(Int)
        case offline(Error)
    }

    // MARK: Requests

    private static func get(_ path: String, _ query: [String: String]) async throws -> Data {
        var components = URLComponents(string: base + path)!
        components.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw Failure.badResponse(code) }
            return data
        } catch let error as Failure {
            throw error
        } catch {
            throw Failure.offline(error)
        }
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Stops

    /// Bus stops near a point, nearest first.
    static func stops(near latitude: Double, _ longitude: Double) async throws -> [TransitStop] {
        let data = try await get("/stops", [
            "filter[latitude]": String(latitude),
            "filter[longitude]": String(longitude),
            "filter[radius]": "0.01",          // degrees, roughly a kilometre
            "filter[route_type]": "3",         // bus
            "sort": "distance",
            "page[limit]": "12",
        ])

        let page = try decoder.decode(Page<StopResource>.self, from: data)
        return page.data.compactMap { resource in
            guard let lat = resource.attributes.latitude,
                  let lon = resource.attributes.longitude else { return nil }
            return TransitStop(
                id: resource.id, name: resource.attributes.name,
                latitude: lat, longitude: lon
            )
        }
    }

    /// The nearest stop, breaking a tie on whichever has a bus coming soonest.
    ///
    /// Only fetches arrivals more than once when there really is a tie, which
    /// keeps an ordinary refresh to two calls.
    static func nearestStop(to latitude: Double, _ longitude: Double)
        async throws -> (stop: TransitStop, arrivals: [TransitArrival])?
    {
        let candidates = try await stops(near: latitude, longitude)
        guard let closest = candidates.first else { return nil }

        let metres = { (s: TransitStop) in
            distance(latitude, longitude, s.latitude, s.longitude)
        }
        let nearest = metres(closest)
        let tied = candidates.filter { metres($0) - nearest < tieMetres }.prefix(4)

        guard tied.count > 1 else {
            return (closest, try await arrivals(at: closest.id))
        }

        var best: (stop: TransitStop, arrivals: [TransitArrival])?
        for stop in tied {
            let found = (try? await arrivals(at: stop.id)) ?? []
            guard let soonest = found.first?.time else { continue }
            if best == nil || soonest < (best?.arrivals.first?.time ?? .distantFuture) {
                best = (stop, found)
            }
        }
        // Everything tied is equally close, so with no predictions anywhere
        // the first one is as good an answer as any.
        return best ?? (closest, [])
    }

    /// Metres between two points, near enough at city scale.
    static func distance(_ lat1: Double, _ lon1: Double,
                         _ lat2: Double, _ lon2: Double) -> Double {
        let metresPerDegree = 111_320.0
        let dLat = (lat1 - lat2) * metresPerDegree
        let dLon = (lon1 - lon2) * metresPerDegree * cos(lat1 * .pi / 180)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }

    // MARK: Arrivals

    /// Every predicted arrival at a stop, both directions, soonest first.
    static func arrivals(at stopID: String) async throws -> [TransitArrival] {
        let data = try await get("/predictions", [
            "filter[stop]": stopID,
            "include": "route,trip",
            "sort": "time",
            "page[limit]": "40",
        ])

        let page = try decoder.decode(Page<PredictionResource>.self, from: data)

        var included: [String: Resource] = [:]
        for resource in page.included ?? [] {
            included["\(resource.type):\(resource.id)"] = resource
        }

        let now = Date()
        return page.data.compactMap { prediction -> TransitArrival? in
            // A prediction at the end of a line has no departure, and one at
            // the start has no arrival. Either way, one of them is the time.
            guard let when = prediction.attributes.arrivalTime
                    ?? prediction.attributes.departureTime,
                  when > now.addingTimeInterval(-60),
                  let routeID = prediction.relationships?.route?.data?.id
            else { return nil }

            let direction = prediction.attributes.directionId ?? 0
            let route = included["route:\(routeID)"]

            // Bound to its own name first: left in the optional chain, the
            // flatMap would be Sequence's, over the characters of the id.
            let tripID: String? = prediction.relationships?.trip?.data?.id
            let trip = tripID.flatMap { included["trip:\($0)"] }

            // Where this direction of the route ends up, which is what the
            // destination labels on the screen are.
            var endOfLine: String?
            if let ends = route?.attributes.directionDestinations,
               ends.indices.contains(direction) {
                endOfLine = ends[direction]
            }

            let headsign = trip?.attributes.headsign ?? endOfLine ?? "—"

            return TransitArrival(
                id: prediction.id,
                route: route?.attributes.shortName ?? routeID,
                headsign: headsign,
                direction: endOfLine ?? headsign,
                directionID: direction,
                time: when,
                tripID: tripID,
                stopSequence: prediction.attributes.stopSequence
            )
        }
        .sorted { $0.time < $1.time }
    }

    // MARK: Alerts

    /// Alerts in force right now on the given routes. A detour or suspension
    /// is the thing that actually changes what you should do.
    static func alerts(routes: [String]) async throws -> [TransitAlert] {
        let names = Set(routes).sorted()
        guard !names.isEmpty else { return [] }

        let data = try await get("/alerts", [
            "filter[route]": names.joined(separator: ","),
            "filter[datetime]": "NOW",
        ])

        let page = try decoder.decode(Page<AlertResource>.self, from: data)
        return page.data.compactMap { alert in
            let text = alert.attributes.header
                ?? alert.attributes.shortHeader
                ?? alert.attributes.serviceEffect
            guard let text, !text.isEmpty else { return nil }

            let route = alert.attributes.informedEntity?
                .compactMap(\.route)
                .first { names.contains($0) }

            return TransitAlert(
                id: alert.id,
                route: route ?? names.joined(separator: ", "),
                effect: alert.attributes.effect ?? "ALERT",
                header: text
            )
        }
    }

    // MARK: Vehicles

    /// Buses currently running the given routes.
    ///
    /// `arrivals` is passed in so each bus can be tied to the arrival it is
    /// going to become, which is the only way to say how many stops out it is.
    static func vehicles(routes: [String],
                         matching arrivals: [TransitArrival]) async throws -> [TransitVehicle] {
        let names = Set(routes).sorted()
        guard !names.isEmpty else { return [] }

        let data = try await get("/vehicles", [
            "filter[route]": names.joined(separator: ","),
            "page[limit]": "60",
        ])

        let page = try decoder.decode(Page<VehicleResource>.self, from: data)

        // Where each trip is due to reach the stop being watched.
        var sequenceByTrip: [String: Int] = [:]
        for arrival in arrivals {
            if let trip = arrival.tripID, let sequence = arrival.stopSequence {
                sequenceByTrip[trip] = sequence
            }
        }

        return page.data.compactMap { vehicle -> TransitVehicle? in
            guard let lat = vehicle.attributes.latitude,
                  let lon = vehicle.attributes.longitude,
                  let routeID = vehicle.relationships?.route?.data?.id
            else { return nil }

            let tripID: String? = vehicle.relationships?.trip?.data?.id

            var stopsAway: Int?
            if let tripID,
               let mine = sequenceByTrip[tripID],
               let theirs = vehicle.attributes.currentStopSequence {
                stopsAway = mine - theirs
            }

            return TransitVehicle(
                id: vehicle.id,
                route: routeID,
                latitude: lat,
                longitude: lon,
                label: vehicle.attributes.label ?? vehicle.id,
                status: vehicle.attributes.currentStatus ?? "",
                tripID: tripID,
                stopsAway: stopsAway
            )
        }
    }

    // MARK: JSON:API shapes

    private struct Page<T: Decodable>: Decodable {
        let data: [T]
        var included: [Resource]?
    }

    /// `included` carries routes and trips together, so every field is
    /// optional and the type tag says which is which.
    private struct Resource: Decodable {
        let id: String
        let type: String
        let attributes: Attributes

        struct Attributes: Decodable {
            let shortName: String?                  // route
            let directionDestinations: [String]?    // route
            let headsign: String?                   // trip
        }
    }

    private struct StopResource: Decodable {
        let id: String
        let attributes: Attributes

        struct Attributes: Decodable {
            let name: String
            let latitude: Double?
            let longitude: Double?
        }
    }

    private struct PredictionResource: Decodable {
        let id: String
        let attributes: Attributes
        let relationships: Relationships?

        struct Attributes: Decodable {
            let arrivalTime: Date?
            let departureTime: Date?
            let directionId: Int?
            let stopSequence: Int?
        }

        struct Relationships: Decodable {
            let route: Reference?
            let trip: Reference?
        }

        struct Reference: Decodable {
            let data: Item?
            struct Item: Decodable { let id: String }
        }
    }

    private struct VehicleResource: Decodable {
        let id: String
        let attributes: Attributes
        let relationships: PredictionResource.Relationships?

        struct Attributes: Decodable {
            let latitude: Double?
            let longitude: Double?
            let label: String?
            let currentStatus: String?
            let currentStopSequence: Int?
        }
    }

    private struct AlertResource: Decodable {
        let id: String
        let attributes: Attributes

        struct Attributes: Decodable {
            let header: String?
            let shortHeader: String?
            let serviceEffect: String?
            let effect: String?
            let informedEntity: [Entity]?

            struct Entity: Decodable { let route: String? }
        }
    }
}

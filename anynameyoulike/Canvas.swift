import Foundation

// MARK: - What a class is

/// One real course, reduced to the two things worth showing.
///
/// Canvas course names arrive as an administrative mouthful —
/// "CS5610 17395 Web Development SEC 02 Fall 2026 [BOS-1-TR]" — and the
/// only parts that mean anything on a phone are the code and the subject.
nonisolated struct CanvasClass: Codable, Equatable, Identifiable, Hashable {
    var id: Int
    /// "CS5610"
    var code: String
    /// "Web Development"
    var title: String
}

/// A piece of work with a real deadline. Assignments without a due date are
/// never built into one of these: an undated assignment cannot be ranked,
/// cannot be reminded about, and only crowds the screen.
nonisolated struct CanvasAssignment: Codable, Equatable, Identifiable, Hashable {
    var id: Int
    var courseID: Int
    var name: String
    var dueAt: Date
    var link: URL?
    /// Submitted, graded, or excused — anything that means hands off.
    var isDone: Bool
}

/// Everything the screens draw, and everything that gets cached.
nonisolated struct CanvasSnapshot: Codable, Equatable {
    var classes: [CanvasClass] = []
    var assignments: [CanvasAssignment] = []
    var fetchedAt: Date?

    var isEmpty: Bool { classes.isEmpty && assignments.isEmpty }

    func `class`(_ id: Int) -> CanvasClass? {
        classes.first { $0.id == id }
    }

    /// Unsubmitted work, soonest first. Overdue items stay in — a missed
    /// deadline is still worth seeing.
    var outstanding: [CanvasAssignment] {
        assignments.filter { !$0.isDone }.sorted { $0.dueAt < $1.dueAt }
    }

    func outstanding(in courseID: Int) -> [CanvasAssignment] {
        outstanding.filter { $0.courseID == courseID }
    }

    var next: CanvasAssignment? { outstanding.first }

    /// How much is due in the next seven days, for the small count on the
    /// home card.
    func dueThisWeek(from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let horizon = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        return outstanding.filter { $0.dueAt >= now && $0.dueAt <= horizon }.count
    }

    /// The window the detail screen shows, past-due work included.
    func soon(within days: Int = 14,
              from now: Date = Date(),
              calendar: Calendar = .current) -> [CanvasAssignment] {
        let horizon = calendar.date(byAdding: .day, value: days, to: now) ?? now
        return outstanding.filter { $0.dueAt <= horizon }
    }
}

// MARK: - Reading a course name

/// Pulling a class out of the string Canvas calls a course name.
///
/// The shape is `CODE SECTIONNUMBER Title SEC NN Term [CAMPUS]`. Anything
/// that does not fit is not a class — it is a sandbox, a training module, an
/// orientation shell — and gets dropped rather than guessed at.
nonisolated enum CanvasCourseName {

    /// Subjects worth naming properly rather than echoing the registrar.
    static let known: [String: String] = [
        "CS5610": "Web Development",
        "CS6620": "Cloud Computing",
    ]

    /// Nil when the name does not look like a real course.
    static func parse(_ raw: String, id: Int) -> CanvasClass? {
        let words = raw.split(separator: " ").map(String.init)
        guard words.count >= 4 else { return nil }

        guard let (code, rest) = code(from: words) else { return nil }

        // The registrar's own section number sits between the code and the
        // subject, and is of no interest.
        guard rest.count >= 3, rest[0].allSatisfy(\.isNumber) else { return nil }

        // "SEC" closes the subject. Without it this is not a course name.
        guard let sec = rest.firstIndex(of: "SEC"), sec > 1 else { return nil }

        let title = rest[1..<sec].joined(separator: " ")
        guard !title.isEmpty else { return nil }

        return CanvasClass(id: id, code: code, title: known[code] ?? title)
    }

    /// "CS5610" as one word, or "CS 5610" as two. Returns the code and
    /// whatever is left after it.
    private static func code(from words: [String]) -> (String, [String])? {
        let first = words[0]

        let letters = first.prefix { $0.isLetter }
        let digits = first.dropFirst(letters.count)

        if letters.count >= 2, letters.count <= 4, digits.count == 4,
           digits.allSatisfy(\.isNumber) {
            return (first.uppercased(), Array(words.dropFirst()))
        }

        if first.count >= 2, first.count <= 4, first.allSatisfy(\.isLetter),
           words.count > 1, words[1].count == 4, words[1].allSatisfy(\.isNumber) {
            return ((first + words[1]).uppercased(), Array(words.dropFirst(2)))
        }

        return nil
    }
}

// MARK: - When a thing is actually due

/// Turning a timestamp into the way you would say it out loud.
///
/// The one rule that matters: Canvas runs on Pacific time and this phone does
/// not. A deadline at 2:59 AM Eastern is 11:59 PM the night before in
/// California, which is the deadline the professor actually set. Anything
/// landing in the small hours therefore belongs to the previous evening, and
/// calling it "tomorrow" would hand you a day you do not have.
nonisolated enum CanvasDue {

    /// Before this hour, the deadline belongs to the night before.
    static let nightEndsAt = 6

    /// Midnight of the day a deadline really belongs to.
    static func effectiveDay(for due: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: due)
        let day = hour < nightEndsAt
            ? calendar.date(byAdding: .day, value: -1, to: due) ?? due
            : due
        return calendar.startOfDay(for: day)
    }

    /// Whether to say "night". True for the small hours, and for anything
    /// from six in the evening onwards.
    static func isNight(_ due: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: due)
        return hour < nightEndsAt || hour >= 18
    }

    /// "Tonight", "Tomorrow night", "Wednesday night", "Next Monday".
    static func dayPhrase(for due: Date,
                          from now: Date = Date(),
                          calendar: Calendar = .current) -> String {
        let day = effectiveDay(for: due, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let away = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let night = isNight(due, calendar: calendar)

        switch away {
        case ..<0:
            return "Overdue"
        case 0:
            return night ? "Tonight" : "Today"
        case 1:
            return night ? "Tomorrow night" : "Tomorrow"
        case 2...6:
            return weekday(of: day, calendar: calendar) + (night ? " night" : "")
        case 7...13:
            // Far enough out that the hour of day stops mattering.
            return "Next " + weekday(of: day, calendar: calendar)
        default:
            return shaped("MMM d", calendar).string(from: day)
        }
    }

    /// "by 10 PM", "by 2:59 AM".
    static func timePhrase(for due: Date, calendar: Calendar = .current) -> String {
        let minute = calendar.component(.minute, from: due)
        let shape = minute == 0 ? "h a" : "h:mm a"
        return "by " + shaped(shape, calendar).string(from: due)
    }

    /// "Wednesday night, by 10 PM"
    static func phrase(for due: Date,
                       from now: Date = Date(),
                       calendar: Calendar = .current) -> String {
        dayPhrase(for: due, from: now, calendar: calendar)
            + ", " + timePhrase(for: due, calendar: calendar)
    }

    private static func weekday(of day: Date, calendar: Calendar) -> String {
        shaped("EEEE", calendar).string(from: day)
    }

    /// Built per call rather than shared.
    ///
    /// A cached formatter would have to have its calendar and time zone set
    /// on every use to stay correct, and these are read from notification
    /// scheduling as well as from drawing — mutating one shared object from
    /// two places is the kind of race that shows up as a wrong weekday once a
    /// month and is never reproducible. Building one costs microseconds.
    private static func shaped(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale ?? .current
        f.dateFormat = format
        return f
    }
}

// MARK: - Talking to Canvas

/// The Canvas REST client.
///
/// The token never passes through here as anything but a function argument
/// read from the Keychain at the moment of the call. It is not stored on the
/// type, not logged, and not written anywhere.
nonisolated enum CanvasAPI {
    static let host = "northeastern.instructure.com"

    enum Failure: Error, Equatable {
        case noToken
        case unauthorised
        case offline
        case badResponse(Int)
        /// A 200 whose body did not decode. Says where it went wrong,
        /// because the status code alone is useless here.
        case unreadable(String)

        /// What the screens actually say. The 401 case is the one that
        /// matters: a Canvas token is revoked or expires silently, and
        /// without being told, a stale token just looks like an empty term.
        var message: String {
            switch self {
            case .noToken: return "Connect Canvas to see assignments"
            case .unauthorised: return "Canvas token needs replacing"
            case .offline: return "No connection"
            case .badResponse(let code): return "Canvas error \(code)"
            case .unreadable(let why): return "Canvas replied oddly: \(why)"
            }
        }

        var needsNewToken: Bool { self == .unauthorised }
    }

    // MARK: Wire shapes

    private struct Course: Decodable {
        var id: Int
        var name: String?

        enum CodingKeys: String, CodingKey { case id, name }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            id = try identifier(box, .id)
            name = try box.decodeIfPresent(String.self, forKey: .name)
        }
    }

    private struct Assignment: Decodable {
        var id: Int
        var name: String?
        var dueAt: Date?
        var htmlUrl: URL?
        var submission: Submission?

        enum CodingKeys: String, CodingKey {
            case id, name, dueAt, htmlUrl, submission
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            id = try identifier(box, .id)
            name = try box.decodeIfPresent(String.self, forKey: .name)
            dueAt = try box.decodeIfPresent(Date.self, forKey: .dueAt)
            htmlUrl = try box.decodeIfPresent(URL.self, forKey: .htmlUrl)
            submission = try box.decodeIfPresent(Submission.self, forKey: .submission)
        }
    }

    /// An id arrives as a number normally and as a string if anything ever
    /// asks Canvas for string ids. Taking both costs a line and removes a
    /// whole class of silent decode failure.
    static func identifier<K: CodingKey>(_ box: KeyedDecodingContainer<K>,
                                         _ key: K) throws -> Int {
        if let number = try? box.decode(Int.self, forKey: key) { return number }
        if let text = try? box.decode(String.self, forKey: key),
           let number = Int(text) { return number }

        throw DecodingError.typeMismatch(Int.self, DecodingError.Context(
            codingPath: box.codingPath + [key],
            debugDescription: "id is neither a number nor a numeric string"
        ))
    }

    private struct Submission: Decodable {
        var submittedAt: Date?
        var workflowState: String?
        var excused: Bool?

        /// Anything that means the work has left your hands.
        var isDone: Bool {
            if excused == true { return true }
            if submittedAt != nil { return true }
            return ["submitted", "pending_review", "graded"]
                .contains(workflowState ?? "")
        }
    }

    // MARK: The one call the app makes

    static func load(token: String) async throws -> CanvasSnapshot {
        let courses: [Course] = try await all(
            path: "/api/v1/courses",
            query: [
                URLQueryItem(name: "enrollment_state", value: "active"),
                URLQueryItem(name: "per_page", value: "100"),
            ],
            token: token
        )

        let classes = courses.compactMap { course -> CanvasClass? in
            guard let name = course.name else { return nil }
            return CanvasCourseName.parse(name, id: course.id)
        }

        // Each course is an independent round trip, so they go out together
        // rather than one after another.
        var assignments: [CanvasAssignment] = []

        try await withThrowingTaskGroup(of: [CanvasAssignment].self) { group in
            for subject in classes {
                group.addTask { try await work(in: subject, token: token) }
            }
            for try await batch in group {
                assignments.append(contentsOf: batch)
            }
        }

        return CanvasSnapshot(
            classes: classes.sorted { $0.code < $1.code },
            assignments: assignments.sorted { $0.dueAt < $1.dueAt },
            fetchedAt: Date()
        )
    }

    private static func work(in subject: CanvasClass,
                             token: String) async throws -> [CanvasAssignment] {
        let raw: [Assignment] = try await all(
            path: "/api/v1/courses/\(subject.id)/assignments",
            query: [
                URLQueryItem(name: "include[]", value: "submission"),
                URLQueryItem(name: "order_by", value: "due_at"),
                URLQueryItem(name: "per_page", value: "100"),
            ],
            token: token
        )

        return raw.compactMap { item in
            // No due date, no place in a list sorted by deadline.
            guard let dueAt = item.dueAt else { return nil }

            return CanvasAssignment(
                id: item.id,
                courseID: subject.id,
                name: item.name ?? "Untitled",
                dueAt: dueAt,
                link: item.htmlUrl,
                isDone: item.submission?.isDone ?? false
            )
        }
    }

    // MARK: Paging

    /// Follows the `Link` header to the end. Canvas caps a page at 100 and
    /// says so only in that header, so a term with more work than that would
    /// otherwise silently lose the tail of it.
    private static func all<T: Decodable>(path: String,
                                          query: [URLQueryItem],
                                          token: String) async throws -> [T] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query

        guard var url = components.url else { throw Failure.badResponse(0) }

        var collected: [T] = []
        // A guard against a server that keeps handing back a next link.
        for _ in 0..<20 {
            let (items, next): ([T], URL?) = try await page(url, token: token)
            collected.append(contentsOf: items)
            guard let next else { break }
            url = next
        }
        return collected
    }

    private static func page<T: Decodable>(_ url: URL,
                                           token: String) async throws -> ([T], URL?) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Plain JSON on purpose. Canvas also offers
        // "application/json+canvas-string-ids", which quotes every id — and
        // every id here is an Int, so asking for that silently broke every
        // decode and surfaced as "Canvas error 200".
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw Failure.badResponse(0)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw Failure.unauthorised
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.badResponse(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            let items = try decoder.decode([T].self, from: readable(data))
            return (items, nextPage(in: http.value(forHTTPHeaderField: "Link")))
        } catch let problem as DecodingError {
            throw Failure.unreadable(describe(problem))
        } catch {
            throw Failure.unreadable("unexpected shape")
        }

    }

    /// Canvas can prefix a response with `while(1);` to spoil a naive
    /// cross-site read of it. That is not JSON, and the decoder stops dead
    /// on the first character.
    static func readable(_ data: Data) -> Data {
        let guardText = Data("while(1);".utf8)
        guard data.starts(with: guardText) else { return data }
        return data.dropFirst(guardText.count)
    }

    /// Enough to say which field was wrong, without a wall of text.
    private static func describe(_ problem: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }
            return keys.isEmpty ? "the reply" : keys.joined(separator: ".")
        }

        switch problem {
        case .keyNotFound(let key, let context):
            return "\(path(context)) has no \(key.stringValue)"
        case .typeMismatch(let type, let context):
            return "\(path(context)) is not a \(type)"
        case .valueNotFound(_, let context):
            return "\(path(context)) was empty"
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty ? "not JSON" : "\(path(context)) is malformed"
        @unknown default:
            return "unexpected shape"
        }
    }

    /// `<https://…&page=2>; rel="next",<https://…>; rel="last"`
    static func nextPage(in header: String?) -> URL? {
        guard let header else { return nil }

        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";")
            guard pieces.count >= 2,
                  pieces.dropFirst().contains(where: {
                      $0.contains("rel=\"next\"") || $0.contains("rel=next")
                  })
            else { continue }

            let raw = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.hasPrefix("<"), raw.hasSuffix(">") else { continue }
            return URL(string: String(raw.dropFirst().dropLast()))
        }
        return nil
    }
}

import BackgroundTasks
import Foundation
import Observation
import UserNotifications

// MARK: - Keeping the last answer

/// The last good fetch, on disk.
///
/// Deliberately not in kalla.json. This is a copy of something Canvas owns,
/// not data of yours, so it has no business in the backup you export or in
/// the document a restore would overwrite. It lives in Application Support
/// rather than Documents so it stays out of the Files app, and out of
/// Caches so the system cannot evict the one thing that makes the screen
/// work on a dead connection.
nonisolated enum CanvasCache {

    static var url: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]

        try? FileManager.default.createDirectory(
            at: support, withIntermediateDirectories: true
        )

        return support.appendingPathComponent("canvas.json")
    }

    static func read() -> CanvasSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CanvasSnapshot.self, from: data)
    }

    static func write(_ snapshot: CanvasSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Reminders

/// Two nudges per piece of work: one two mornings before, one the morning
/// before. Nine in the morning, which is early enough to do something about
/// it and late enough not to be the alarm.
nonisolated enum CanvasReminders {

    static let prefix = "canvas-"
    static let hour = 9

    /// iOS allows 64 pending notifications per app and silently drops the
    /// rest. The trash rota, the nightly reminder and the two signing
    /// warnings all need slots, so assignments take at most forty and the
    /// soonest ones win.
    static let budget = 40

    struct Nudge: Equatable {
        var identifier: String
        var title: String
        var body: String
        var fire: Date
    }

    /// Everything that should be pending, soonest first and already capped.
    static func plan(for snapshot: CanvasSnapshot,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> [Nudge] {
        var nudges: [Nudge] = []

        for assignment in snapshot.outstanding {
            guard let subject = snapshot.class(assignment.courseID) else { continue }

            let day = CanvasDue.effectiveDay(for: assignment.dueAt, calendar: calendar)
            let time = CanvasDue.timePhrase(for: assignment.dueAt, calendar: calendar)
            let body = "\(assignment.name), \(subject.title), \(time)"

            for lead in [2, 1] {
                guard let morning = morning(lead, before: day, calendar: calendar),
                      morning > now
                else { continue }

                // Said as it will read on the day it arrives, not as it reads
                // now — "Due tomorrow night" has to be true tomorrow.
                let phrase = CanvasDue.dayPhrase(
                    for: assignment.dueAt, from: morning, calendar: calendar
                )

                nudges.append(Nudge(
                    identifier: "\(prefix)\(assignment.id)-\(lead)d",
                    title: lead == 2 ? "Coming up \(phrase)" : "Due \(lowered(phrase))",
                    body: body,
                    fire: morning
                ))
            }
        }

        return nudges.sorted { $0.fire < $1.fire }.prefix(budget).map { $0 }
    }

    private static func morning(_ lead: Int,
                                before day: Date,
                                calendar: Calendar) -> Date? {
        guard let earlier = calendar.date(byAdding: .day, value: -lead, to: day) else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: earlier)
    }

    /// "Tomorrow night" reads wrong after "Due".
    private static func lowered(_ phrase: String) -> String {
        guard let first = phrase.first else { return phrase }
        return first.lowercased() + phrase.dropFirst()
    }

    /// Clears every assignment reminder and lays down the current set.
    ///
    /// Wiping the lot first is what cancels reminders for work that has since
    /// been handed in: anything not in the new plan simply does not come
    /// back. Identifiers carry the assignment id, so a due date that moved
    /// replaces its old reminder rather than adding a second one.
    static func reschedule(_ snapshot: CanvasSnapshot, now: Date = Date()) async {
        await place(snapshot, now: now)
        await Shared.notifications.measure()
    }

    private static func place(_ snapshot: CanvasSnapshot, now: Date) async {
        let center = UNUserNotificationCenter.current()

        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }

        center.removePendingNotificationRequests(withIdentifiers: stale)

        let nudges = plan(for: snapshot, now: now)
        guard !nudges.isEmpty else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        else { return }

        for nudge in nudges {
            let content = UNMutableNotificationContent()
            content.title = nudge.title
            content.body = nudge.body
            content.sound = .default

            let parts = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: nudge.fire
            )

            try? await center.add(
                UNNotificationRequest(
                    identifier: nudge.identifier,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: parts, repeats: false
                    )
                )
            )
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let mine = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }

        center.removePendingNotificationRequests(withIdentifiers: mine)
        await Shared.notifications.measure()
    }
}

// MARK: - The engine

/// What the Canvas screens read from.
@Observable
final class CanvasBoard {

    private(set) var snapshot: CanvasSnapshot
    private(set) var failure: CanvasAPI.Failure?
    private(set) var isLoading = false

    /// Mirrors the Keychain so views do not hit it on every redraw.
    private(set) var isConnected: Bool

    private var inFlight: Task<Void, Never>?

    init() {
        snapshot = CanvasCache.read() ?? CanvasSnapshot()
        isConnected = CanvasToken.isSaved
        if !isConnected { failure = .noToken }
    }

    var lastUpdated: Date? { snapshot.fetchedAt }

    /// "Updated 4 min ago", or nothing if it has never run.
    var lastUpdatedText: String? {
        guard let fetchedAt = snapshot.fetchedAt else { return nil }

        let shape = RelativeDateTimeFormatter()
        shape.unitsStyle = .abbreviated
        return "Updated " + shape.localizedString(for: fetchedAt, relativeTo: Date())
    }

    // MARK: Fetching

    /// Coalesced: launch, becoming active and a pull-to-refresh can all land
    /// within a second of each other, and one fetch is enough.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }

        let task = Task { await load() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func load() async {
        guard let token = CanvasToken.current else {
            isConnected = false
            failure = .noToken
            return
        }

        isConnected = true
        isLoading = true
        defer { isLoading = false }

        do {
            let fresh = try await CanvasAPI.load(token: token)
            snapshot = fresh
            failure = nil
            CanvasCache.write(fresh)
            await CanvasReminders.reschedule(fresh)
        } catch let problem as CanvasAPI.Failure {
            // The cached snapshot stays on screen. Stale work beats a blank
            // screen, and the banner says how stale it is.
            failure = problem
        } catch {
            failure = .offline
        }
    }

    // MARK: The token

    @discardableResult
    func connect(_ token: String) -> Bool {
        guard CanvasToken.save(token) else { return false }
        isConnected = true
        failure = nil
        return true
    }

    func disconnect() async {
        CanvasToken.remove()
        CanvasCache.clear()
        await CanvasReminders.cancelAll()

        snapshot = CanvasSnapshot()
        failure = .noToken
        isConnected = false
    }
}

// MARK: - Background refresh

/// Lets the reminders stay honest while the app is closed.
///
/// Without this, an assignment submitted on a laptop would keep nagging
/// until the app was next opened, and new work posted mid-week would have no
/// reminder at all.
nonisolated enum CanvasBackground {

    static let identifier = "steps.anynameyoulike.canvas.refresh"

    /// Must run before the app finishes launching, or the scheduler refuses
    /// the identifier for the life of the process.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: nil
        ) { task in
            handle(task)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // iOS treats this as the earliest acceptable moment, not a promise.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask) {
        // Queued again first: if the work below is cut short, there is still
        // a next attempt booked.
        schedule()

        let work = Task { @MainActor in
            await Shared.canvas.refresh()
            task.setTaskCompleted(success: Shared.canvas.failure == nil)
        }

        task.expirationHandler = { work.cancel() }
    }
}

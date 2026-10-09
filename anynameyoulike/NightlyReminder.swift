import Foundation
import UserNotifications

/// One nudge at the end of the day, covering the whole evening routine.
///
/// This used to be two: a step reminder and a grocery one, at different
/// times. That was two interruptions for one habit, so they are now a single
/// notification with a single toggle and a single time.
nonisolated enum NightlyReminder {
    static let identifier = "nightlyReminder"

    /// Marks a tap on this notification, so the app knows to open the export
    /// flow rather than just coming to the front.
    static let category = "nightlyRoutine"

    private static let enabledKey = "nightlyReminderOn"
    private static let hourKey = "nightlyReminderHour"
    private static let minuteKey = "nightlyReminderMinute"
    private static let migratedKey = "nightlyReminderMigratedV1"

    static let defaultHour = 22
    static let defaultMinute = 30

    // MARK: Settings

    static var isEnabled: Bool {
        get {
            migrateIfNeeded()
            return UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var hour: Int {
        get {
            migrateIfNeeded()
            return UserDefaults.standard.object(forKey: hourKey) as? Int ?? defaultHour
        }
        set { UserDefaults.standard.set(newValue, forKey: hourKey) }
    }

    static var minute: Int {
        get {
            migrateIfNeeded()
            return UserDefaults.standard.object(forKey: minuteKey) as? Int ?? defaultMinute
        }
        set { UserDefaults.standard.set(newValue, forKey: minuteKey) }
    }

    /// The stored time as a Date today, for a DatePicker to bind to.
    static var timeAsDate: Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        parts.hour = hour
        parts.minute = minute
        return Calendar.current.date(from: parts) ?? Date()
    }

    static var timeText: String {
        timeAsDate.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Carrying the old settings over

    /// Folds the two old reminders into this one, once.
    ///
    /// On is kept if either of them was on. The time is the later of whatever
    /// was explicitly chosen, because this fires at the end of the day and the
    /// earlier of two settings would go off before the day is done. With
    /// nothing chosen it lands on the new default.
    private static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defer { defaults.set(true, forKey: migratedKey) }

        // Defaults here match what each old reminder used.
        let stepsOn = defaults.object(forKey: "reminderEnabled") as? Bool ?? false
        let groceriesOn = defaults.object(forKey: "groceryReminderOn") as? Bool ?? true
        defaults.set(stepsOn || groceriesOn, forKey: enabledKey)

        var chosen: [(hour: Int, minute: Int)] = []
        if let h = defaults.object(forKey: "reminderHour") as? Int {
            chosen.append((h, defaults.object(forKey: "reminderMinute") as? Int ?? 0))
        }
        if let h = defaults.object(forKey: "groceryReminderHour") as? Int {
            chosen.append((h, defaults.object(forKey: "groceryReminderMinute") as? Int ?? 0))
        }

        if let latest = chosen.max(by: { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }) {
            defaults.set(latest.hour, forKey: hourKey)
            defaults.set(latest.minute, forKey: minuteKey)
        }

        // One source of truth from here on.
        for key in ["reminderEnabled", "reminderHour", "reminderMinute",
                    "groceryReminderOn", "groceryReminderHour", "groceryReminderMinute"] {
            defaults.removeObject(forKey: key)
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["dailyStepReminder", "groceryLogReminder"]
        )
    }

    // MARK: Scheduling

    private static func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Before bed"
        content.body = "Log today's groceries and top up your steps."
        content.sound = .default
        content.interruptionLevel = .active
        content.categoryIdentifier = category
        return content
    }

    private static func permission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge]))
                ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Schedules, or clears, to match the stored settings.
    @discardableResult
    static func apply(at date: Date? = nil) async -> Bool {
        let center = UNUserNotificationCenter.current()

        if let date {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            hour = parts.hour ?? defaultHour
            minute = parts.minute ?? defaultMinute
        }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled else { return false }

        guard await permission() else {
            isEnabled = false
            return false
        }

        var parts = DateComponents()
        parts.hour = hour
        parts.minute = minute

        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content(),
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
                )
            )
            return true
        } catch {
            return false
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
        isEnabled = false
    }

    static func isLive() async -> Bool {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.contains { $0.identifier == identifier }
    }

    /// Fires once, ten seconds out, for checking how it reads.
    @discardableResult
    static func fireTestSoon() async -> Bool {
        guard await permission() else { return false }

        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: "nightlyTest-\(UUID().uuidString)",
                    content: content(),
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
                )
            )
            return true
        } catch {
            return false
        }
    }
}

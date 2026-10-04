import UserNotifications
import Foundation

enum DailyReminder {
    static let identifier = "dailyStepReminder"
    private static let enabledKey = "reminderEnabled"
    private static let hourKey = "reminderHour"
    private static let minuteKey = "reminderMinute"

    private static let message = "Steps hakolo Gubaldu..."

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var hour: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: hourKey) as? Int
            return stored ?? 20
        }
        set { UserDefaults.standard.set(newValue, forKey: hourKey) }
    }

    static var minute: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: minuteKey) as? Int
            return stored ?? 30
        }
        set { UserDefaults.standard.set(newValue, forKey: minuteKey) }
    }

    /// The stored time as a Date today, for binding to a DatePicker.
    static var timeAsDate: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    static var timeText: String {
        timeAsDate.formatted(date: .omitted, time: .shortened)
    }

    private static func makeContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = message
        content.sound = .default
        content.interruptionLevel = .active
        return content
    }

    private static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )) ?? false
    }

    /// Schedules the repeating reminder at the stored time.
    @discardableResult
    static func schedule(at date: Date? = nil) async -> Bool {
        let center = UNUserNotificationCenter.current()

        if let date {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            hour = parts.hour ?? 20
            minute = parts.minute ?? 30
        }

        guard await requestPermission() else {
            isEnabled = false
            return false
        }

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: identifier,
            content: makeContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        do {
            try await center.add(request)
            isEnabled = true
            return true
        } catch {
            isEnabled = false
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

    /// Fires once, 10 seconds out, for checking how it looks.
    @discardableResult
    static func fireTestSoon() async -> Bool {
        guard await requestPermission() else { return false }

        let request = UNNotificationRequest(
            identifier: "reminderTest-\(UUID().uuidString)",
            content: makeContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }
}

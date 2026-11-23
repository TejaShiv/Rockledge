import Foundation
import UserNotifications

/// One word, every evening at eight.
///
/// Deliberately the plainest thing in the app: no streak, no count, no
/// "you haven't meditated in three days". A reminder that keeps score turns
/// a habit into an obligation, and the thing being reminded about here is
/// the opposite of that. It says "Meditate" and then gets out of the way.
///
/// It also carries the nightly backup. Tapping it opens the export sheet,
/// which is the job the old "Before bed" reminder used to do — that one was
/// mostly about logging groceries, which is now done by hand, so the one
/// piece of it worth keeping moved here rather than being thrown out with
/// the rest.
///
/// Costs exactly one of the sixty-four pending notifications iOS allows,
/// because a repeating calendar trigger is held as a single request however
/// many times it fires. See `NotificationCensus`.
nonisolated enum MeditateReminder {
    static let identifier = "meditateReminder"

    /// Marks a tap on this notification, so the app knows to open the export
    /// flow rather than just coming to the front.
    static let category = "meditateRoutine"

    private static let enabledKey = "meditateReminderOn"
    private static let hourKey = "meditateReminderHour"
    private static let minuteKey = "meditateReminderMinute"

    static let defaultHour = 20
    static let defaultMinute = 0

    // MARK: Settings

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var hour: Int {
        get { UserDefaults.standard.object(forKey: hourKey) as? Int ?? defaultHour }
        set { UserDefaults.standard.set(newValue, forKey: hourKey) }
    }

    static var minute: Int {
        get { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? defaultMinute }
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

    // MARK: Scheduling

    private static func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Meditate"
        // No body. The title is the whole message, and an empty body shows
        // as a single line rather than a blank second one.
        content.sound = .default
        // Active, which is as loud as this app can be: banner, sound, screen
        // on. Not .timeSensitive — that one pierces a Focus, but it needs the
        // Time Sensitive Notifications capability, and minting a profile with
        // it fails on a free Apple account. The build breaks rather than
        // degrading, so it is not worth carrying for a setting iOS would
        // quietly ignore anyway.
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

    /// Schedules, or clears, to match the stored settings. Laid down again on
    /// every launch rather than trusted to still be there; adding with the
    /// same identifier replaces, so it cannot stack up.
    @discardableResult
    static func apply(at date: Date? = nil) async -> Bool {
        let scheduled = await place(at: date)
        await Shared.notifications.measure()
        return scheduled
    }

    private static func place(at date: Date?) async -> Bool {
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
                    identifier: "meditateTest-\(UUID().uuidString)",
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

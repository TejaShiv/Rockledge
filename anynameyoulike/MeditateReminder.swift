import Foundation
import UserNotifications

/// One word, every evening at eight.
///
/// Deliberately the plainest thing in the app: no streak, no count, no
/// "you haven't meditated in three days". A reminder that keeps score turns
/// a habit into an obligation, and the thing being reminded about here is
/// the opposite of that. It says "Meditate" and then gets out of the way.
///
/// Costs exactly one of the sixty-four pending notifications iOS allows,
/// because a repeating calendar trigger is held as a single request however
/// many times it fires. See `NotificationCensus`.
nonisolated enum MeditateReminder {
    static let identifier = "meditateReminder"

    static let hour = 20
    static let minute = 0

    private static func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Meditate"
        // No body. The title is the whole message, and an empty body shows
        // as a single line rather than a blank second one.
        content.sound = .default
        // Passive, not active: it should wait on the lock screen rather than
        // interrupt whatever the evening is already doing.
        content.interruptionLevel = .passive
        return content
    }

    private static func permission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound]))
                ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Laid down again on every launch rather than trusted to still be there.
    /// Adding with the same identifier replaces, so this cannot stack up.
    @discardableResult
    static func apply() async -> Bool {
        let scheduled = await place()
        await Shared.notifications.measure()
        return scheduled
    }

    private static func place() async -> Bool {
        guard await permission() else { return false }

        var parts = DateComponents()
        parts.hour = hour
        parts.minute = minute

        do {
            try await UNUserNotificationCenter.current().add(
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
    }

    static func isLive() async -> Bool {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.contains { $0.identifier == identifier }
    }
}

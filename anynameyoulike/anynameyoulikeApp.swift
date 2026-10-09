import SwiftUI
import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// A tap on the nightly reminder goes straight to exporting. The app may
    /// not be running yet, so this only records where to go.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.categoryIdentifier
        guard category == NightlyReminder.category,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier
        else { return }

        await MainActor.run { Shared.router.pending = .export }
    }
}

@main
struct anynameyoulikeApp: App {
    private let presenter = NotificationPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

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

        // Called off from the lock screen, without opening the app.
        if response.actionIdentifier == ArrivalAlert.cancelAction {
            await MainActor.run { Shared.arrival.cancel() }
            return
        }

        guard category == NightlyReminder.category,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier
        else { return }

        await MainActor.run { Shared.router.pending = .export }
    }
}

@main
struct anynameyoulikeApp: App {
    @Environment(\.scenePhase) private var phase

    private let presenter = NotificationPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = presenter
        UNUserNotificationCenter.current().setNotificationCategories(
            [ArrivalAlert.notificationCategory]
        )
        // Touched here on purpose: a region crossing can launch the app
        // straight into the background, and the alert has to be listening
        // before that launch finishes, not when a screen first appears.
        _ = Shared.arrival
        // Has to happen before launch finishes, or the scheduler rejects the
        // identifier for the rest of the process.
        CanvasBackground.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: phase) { _, now in
                    // Booked on the way out, since that is the only moment
                    // the system will actually run it from.
                    if now == .background { CanvasBackground.schedule() }
                }
        }
    }
}

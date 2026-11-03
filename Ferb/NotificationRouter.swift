import Foundation
import Observation
import UserNotifications

/// Receives taps on notifications and tells the UI what to open.
///
/// It's a shared object (not tied to any view) because a tap can be what launches the app,
/// before any screen exists. The flag simply waits until `ContentView` is ready to act on it.
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// iOS only keeps a weak reference to its delegate, so the app holds this one for good.
    static let shared = NotificationRouter()

    /// Set when a start-of-day or end-of-day alert is tapped; cleared by whoever opens Quick update.
    var quickUpdateRequested = false

    /// Runs on the main thread on purpose. When this was `nonisolated`, iOS finished the tap on a
    /// background thread and UIKit's post-tap snapshot work crashed the app (SIGABRT).
    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        if ReminderScheduler.opensQuickUpdate(identifier: identifier) {
            quickUpdateRequested = true
        }
    }
}

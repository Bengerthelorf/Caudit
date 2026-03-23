import Foundation
import UserNotifications

final class NotificationService: NSObject, Sendable, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendQuotaAlert(percentage: Double, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Quota Alert"
        content.body = "5h window usage has reached \(Int(percentage))% (threshold: \(Int(threshold))%)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "quota-alert-\(Int(percentage))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

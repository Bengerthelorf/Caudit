import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "Notification")

final class NotificationService: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Quota Threshold Alerts

    func sendQuotaAlert(percentage: Double, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Quota Alert"
        content.body = "5h window usage has reached \(Int(percentage))% (threshold: \(Int(threshold))%)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "quota-alert-\(Int(threshold))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        logger.info("Sent quota alert: \(Int(percentage))% >= \(Int(threshold))%")
    }

    // MARK: - Session Reset

    func sendSessionResetNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Session Reset"
        content.body = "Your 5-hour quota window has reset. Usage is now at 0%."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "session-reset-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        logger.info("Sent session reset notification")
    }

    // MARK: - Weekly Quota Alerts

    func sendWeeklyQuotaAlert(percentage: Double, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Weekly Quota Alert"
        content.body = "7-day usage has reached \(Int(percentage))% (threshold: \(Int(threshold))%)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "weekly-quota-alert-\(Int(threshold))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        logger.info("Sent weekly quota alert: \(Int(percentage))% >= \(Int(threshold))%")
    }

    // MARK: - Budget Alerts

    func sendBudgetAlert(type: String, currentCost: Double, budget: Double, thresholdPercent: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(type) Budget Alert"
        content.body = "\(type) spend $\(String(format: "%.2f", currentCost)) has reached \(thresholdPercent)% of $\(String(format: "%.2f", budget)) budget"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(type.lowercased())-budget-alert-\(thresholdPercent)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        logger.info("Sent \(type) budget alert: $\(String(format: "%.2f", currentCost)) >= \(thresholdPercent)% of $\(String(format: "%.2f", budget))")
    }

    // MARK: - Delegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // MARK: - Threshold Logic

    /// Checks multiple thresholds and returns which ones should fire.
    /// A threshold fires if `current >= threshold && previousLevel < threshold`.
    static func thresholdsToFire(
        current: Double,
        previousLevel: Double,
        enabledThresholds: Set<Int>
    ) -> [Int] {
        enabledThresholds
            .filter { threshold in
                let t = Double(threshold)
                return current >= t && previousLevel < t
            }
            .sorted()
    }

    /// Checks if a session reset occurred (usage dropped from >0 to 0).
    static func isSessionReset(current: Double, previousLevel: Double) -> Bool {
        previousLevel > 0 && current == 0
    }
}

import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "Webhook")

enum WebhookPreset: String, Codable, CaseIterable, Identifiable {
    case custom = "Custom"
    case slack = "Slack"
    case discord = "Discord"
    case telegram = "Telegram"

    var id: String { rawValue }
}

struct WebhookConfig: Codable, Equatable {
    var enabled: Bool = false
    var preset: WebhookPreset = .custom
    /// Webhook URL (contains auth tokens for Slack/Discord — stored via Keychain by AppState)
    var url: String = ""
    /// Telegram-specific: bot token
    var telegramBotToken: String = ""
    /// Telegram-specific: chat ID
    var telegramChatId: String = ""
}

/// Keychain storage for webhook secrets.
enum WebhookKeychain {
    private static let service = "cc.ffitch.Claudit.webhook"

    static func save(_ config: WebhookConfig) {
        let secrets: [String: String] = [
            "url": config.url,
            "telegramBotToken": config.telegramBotToken,
            "telegramChatId": config.telegramChatId,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: secrets) else { return }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "webhookSecrets",
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> (url: String, botToken: String, chatId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "webhookSecrets",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return ("", "", "")
        }
        return (dict["url"] ?? "", dict["telegramBotToken"] ?? "", dict["telegramChatId"] ?? "")
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "webhookSecrets"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class WebhookService: Sendable {
    static let shared = WebhookService()
    private init() {}

    /// Send a notification via webhook. Fire-and-forget from background task.
    func send(title: String, body: String, config: WebhookConfig) {
        guard config.enabled else { return }

        Task.detached {
            do {
                try await self.deliver(title: title, body: body, config: config)
            } catch {
                logger.warning("Webhook delivery failed: \(error.localizedDescription)")
            }
        }
    }

    private func deliver(title: String, body: String, config: WebhookConfig) async throws {
        let (url, payload) = try buildRequest(title: title, body: body, config: config)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = payload

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            logger.warning("Webhook returned HTTP \(httpResponse.statusCode)")
        }
    }

    private func buildRequest(title: String, body: String, config: WebhookConfig) throws -> (URL, Data) {
        switch config.preset {
        case .slack:
            return try buildSlack(title: title, body: body, url: config.url)
        case .discord:
            return try buildDiscord(title: title, body: body, url: config.url)
        case .telegram:
            return try buildTelegram(title: title, body: body, config: config)
        case .custom:
            return try buildCustom(title: title, body: body, url: config.url)
        }
    }

    // MARK: - Slack

    private func buildSlack(title: String, body: String, url: String) throws -> (URL, Data) {
        guard let endpoint = URL(string: url) else { throw WebhookError.invalidURL }
        let payload: [String: Any] = [
            "text": "\(title): \(body)",
            "blocks": [
                [
                    "type": "section",
                    "text": ["type": "mrkdwn", "text": "*\(title)*\n\(body)"]
                ]
            ]
        ]
        return (endpoint, try JSONSerialization.data(withJSONObject: payload))
    }

    // MARK: - Discord

    private func buildDiscord(title: String, body: String, url: String) throws -> (URL, Data) {
        guard let endpoint = URL(string: url) else { throw WebhookError.invalidURL }
        let payload: [String: Any] = [
            "embeds": [[
                "title": title,
                "description": body,
                "color": 3447003, // Blue
                "footer": ["text": "Claudit"],
                "timestamp": ClauditFormatter.formatISO8601(Date())
            ]]
        ]
        return (endpoint, try JSONSerialization.data(withJSONObject: payload))
    }

    // MARK: - Telegram

    private func buildTelegram(title: String, body: String, config: WebhookConfig) throws -> (URL, Data) {
        guard !config.telegramBotToken.isEmpty, !config.telegramChatId.isEmpty else {
            throw WebhookError.missingConfig
        }
        let urlStr = "https://api.telegram.org/bot\(config.telegramBotToken)/sendMessage"
        guard let endpoint = URL(string: urlStr) else { throw WebhookError.invalidURL }
        let payload: [String: Any] = [
            "chat_id": config.telegramChatId,
            "text": "<b>\(Self.escapeHTML(title))</b>\n\(Self.escapeHTML(body))",
            "parse_mode": "HTML"
        ]
        return (endpoint, try JSONSerialization.data(withJSONObject: payload))
    }

    // MARK: - Custom

    private func buildCustom(title: String, body: String, url: String) throws -> (URL, Data) {
        guard let endpoint = URL(string: url) else { throw WebhookError.invalidURL }
        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "timestamp": ClauditFormatter.formatISO8601(Date()),
            "source": "Claudit"
        ]
        return (endpoint, try JSONSerialization.data(withJSONObject: payload))
    }

    // MARK: - Format Helpers

    /// Format a quota alert for webhook delivery.
    static func formatQuotaAlert(percentage: Double, threshold: Double, windowType: String) -> (title: String, body: String) {
        (
            title: "\(windowType) Quota Alert",
            body: "\(windowType) usage at \(Int(percentage))% (threshold: \(Int(threshold))%)"
        )
    }

    static func formatBudgetAlert(type: String, cost: Double, budget: Double, thresholdPercent: Int) -> (title: String, body: String) {
        (
            title: "\(type) Budget Alert",
            body: "Spend $\(String(format: "%.2f", cost)) reached \(thresholdPercent)% of $\(String(format: "%.2f", budget)) budget"
        )
    }

    static func formatSessionReset() -> (title: String, body: String) {
        ("Session Reset", "5-hour quota window has reset to 0%")
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum WebhookError: LocalizedError {
    case invalidURL
    case missingConfig

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid webhook URL"
        case .missingConfig: return "Missing webhook configuration"
        }
    }
}

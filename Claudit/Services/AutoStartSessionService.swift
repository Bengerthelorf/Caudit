import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "AutoStartSession")

/// Background service that auto-starts a Claude session when quota is at 0%.
///
/// When the 5h quota window shows 0% utilization, this service creates a tiny
/// conversation via the Claude.ai API (sending "Hi" with Haiku), then deletes it.
/// This kicks off the 5-hour window so the quota timer starts counting down.
///
/// Checks every 5 minutes and on system wake.
@MainActor @Observable
final class AutoStartSessionService {
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "autoStartSessionEnabled")
            if isEnabled {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    private(set) var lastAttempt: Date?
    private(set) var lastResult: String?
    private(set) var isRunning = false

    private var timer: Timer?
    private let checkInterval: TimeInterval = 300 // 5 minutes
    private var wakeObserver: Any?

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "autoStartSessionEnabled")
        if isEnabled {
            startTimer()
        }
        setupWakeObserver()
    }

    // Timer and wake observer are cleaned up when the service is deallocated.
    // Since this is a singleton-like service on AppState, it lives for the app lifetime.

    // MARK: - Timer & Wake

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.checkAndStart() }
        }
        // Also check immediately when enabled
        checkAndStart()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func setupWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.isEnabled {
                    // Small delay after wake for network to settle
                    try? await Task.sleep(for: .seconds(5))
                    self.checkAndStart()
                }
            }
        }
    }

    // MARK: - Core Logic

    /// Check if session is at 0% and auto-start if needed.
    func checkAndStart() {
        guard isEnabled, !isRunning else { return }

        // Need a quota reading to determine if at 0%
        // We get this from AppState, but to avoid circular deps, we check via notification
        // For now, the caller (AppState) will call this after quota refresh
    }

    /// Called by AppState when quota refreshes. If utilization is 0%, start a session.
    func onQuotaUpdate(fiveHourUtilization: Double) {
        guard isEnabled, !isRunning else { return }
        guard fiveHourUtilization == 0 else {
            logger.debug("Session already active (\(String(format: "%.1f", fiveHourUtilization))%), skipping auto-start")
            return
        }

        startSession()
    }

    /// Create a throwaway conversation, send "Hi" with Haiku, and delete it.
    private func startSession() {
        guard !isRunning else { return }
        isRunning = true
        lastAttempt = Date()
        lastResult = nil

        Task.detached { [weak self] in
            do {
                try await Self.performAutoStart()
                await MainActor.run { [weak self] in
                    self?.lastResult = "Session started successfully"
                    self?.isRunning = false
                    logger.info("Auto-start session completed")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastResult = "Failed: \(error.localizedDescription)"
                    self?.isRunning = false
                    logger.warning("Auto-start session failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Claude.ai API Calls

    /// Execute the full auto-start flow: create conversation -> send message -> delete conversation.
    private static func performAutoStart() async throws {
        guard let sessionKey = SessionCredentialStore.shared.sessionKey else {
            throw AutoStartError.noSession
        }
        guard let orgId = SessionCredentialStore.shared.organizationId else {
            throw AutoStartError.noSession
        }

        let baseURL = "https://claude.ai/api/organizations/\(orgId)"

        // Step 1: Create a conversation
        let conversationId = try await createConversation(
            baseURL: baseURL,
            sessionKey: sessionKey
        )

        // Step 2: Send a minimal message using Haiku
        do {
            try await sendMessage(
                baseURL: baseURL,
                sessionKey: sessionKey,
                conversationId: conversationId
            )
        } catch {
            // Still try to delete even if send fails
            logger.warning("Send message failed: \(error.localizedDescription), still deleting conversation")
        }

        // Step 3: Delete the conversation
        try await deleteConversation(
            baseURL: baseURL,
            sessionKey: sessionKey,
            conversationId: conversationId
        )
    }

    private static func createConversation(baseURL: String, sessionKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/chat_conversations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let uuid = UUID().uuidString
        let body: [String: Any] = [
            "uuid": uuid,
            "name": ""
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutoStartError.invalidResponse
        }

        await NetworkLogService.shared.record(
            method: "POST", url: url.absoluteString,
            statusCode: httpResponse.statusCode,
            responseBody: String(data: data.prefix(1000), encoding: .utf8),
            duration: Date().timeIntervalSince(start)
        )

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AutoStartError.sessionExpired
            }
            throw AutoStartError.httpError(httpResponse.statusCode)
        }

        // Response contains the conversation with uuid
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let conversationId = json["uuid"] as? String {
            return conversationId
        }

        return uuid
    }

    private static func sendMessage(baseURL: String, sessionKey: String, conversationId: String) async throws {
        let url = URL(string: "\(baseURL)/chat_conversations/\(conversationId)/completion")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "prompt": "Hi",
            "timezone": TimeZone.current.identifier,
            "model": "claude-haiku-4-5-20251001",
            "attachments": [] as [Any],
            "files": [] as [Any]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutoStartError.invalidResponse
        }

        await NetworkLogService.shared.record(
            method: "POST", url: url.absoluteString,
            statusCode: httpResponse.statusCode,
            responseBody: String(data: data.prefix(500), encoding: .utf8),
            duration: Date().timeIntervalSince(start)
        )

        guard httpResponse.statusCode == 200 else {
            throw AutoStartError.httpError(httpResponse.statusCode)
        }
    }

    private static func deleteConversation(baseURL: String, sessionKey: String, conversationId: String) async throws {
        let url = URL(string: "\(baseURL)/chat_conversations/\(conversationId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutoStartError.invalidResponse
        }

        await NetworkLogService.shared.record(
            method: "DELETE", url: url.absoluteString,
            statusCode: httpResponse.statusCode,
            duration: Date().timeIntervalSince(start)
        )

        // 200 or 204 are both success
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
            logger.warning("Delete conversation returned \(httpResponse.statusCode): \(bodyStr)")
            throw AutoStartError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

enum AutoStartError: LocalizedError, Equatable {
    case noSession
    case sessionExpired
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "No Claude.ai session. Sign in via Settings."
        case .sessionExpired:
            return "Claude.ai session expired. Sign in again."
        case .invalidResponse:
            return "Invalid response from Claude.ai."
        case .httpError(let code):
            return "Claude.ai HTTP \(code)"
        }
    }
}

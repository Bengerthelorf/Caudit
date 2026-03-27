import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "Quota")

// MARK: - Quota Source Configuration

enum QuotaSource: String, CaseIterable {
    case rateLimitHeaders = "Auto (Rate Limit Headers)"
    case oauthAPI = "OAuth API"
    case claudeSession = "Claude.ai Session"
}

// MARK: - Quota Provider Protocol

protocol QuotaProvider: Sendable {
    func fetchQuota() async throws -> QuotaInfo
}

// MARK: - Unified Quota Service

final class QuotaService: Sendable {
    private static let maxRetries = 3
    private static let retryBaseDelay: TimeInterval = 5.0
    private static let retryMaxDelay: TimeInterval = 30.0

    private let rateLimitProvider = RateLimitHeadersQuotaProvider()
    private let oauthProvider = OAuthAPIQuotaProvider()
    private let sessionProvider = SessionCookieQuotaProvider()

    func fetchQuota(source: QuotaSource) async throws -> QuotaInfo {
        let provider: QuotaProvider = switch source {
        case .rateLimitHeaders: rateLimitProvider
        case .oauthAPI: oauthProvider
        case .claudeSession: sessionProvider
        }

        for attempt in 0..<Self.maxRetries {
            do {
                return try await provider.fetchQuota()
            } catch QuotaError.rateLimited {
                if attempt < Self.maxRetries - 1 {
                    let delay = min(Self.retryBaseDelay * pow(2.0, Double(attempt)), Self.retryMaxDelay)
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw QuotaError.rateLimited
            }
        }

        throw QuotaError.rateLimited
    }
}

// MARK: - Rate Limit Headers Provider

/// Sends a minimal Haiku API call and reads quota from response headers.
final class RateLimitHeadersQuotaProvider: QuotaProvider {
    func fetchQuota() async throws -> QuotaInfo {
        let token = try CredentialReader.readAccessToken()

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        request.setValue("Claudit/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = Date()
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaError.invalidResponse
        }

        await NetworkLogService.shared.record(
            method: "POST", url: url.absoluteString,
            statusCode: httpResponse.statusCode,
            responseHeaders: httpResponse.allHeaderFields.reduce(into: [:]) { $0["\($1.key)"] = "\($1.value)" },
            duration: Date().timeIntervalSince(start)
        )

        return Self.parseHeaders(httpResponse)
    }

    static func parseHeaders(_ response: HTTPURLResponse) -> QuotaInfo {
        let fiveHourUtil = headerDouble(response, key: "anthropic-ratelimit-unified-5h-utilization") * 100
        let sevenDayUtil = headerDouble(response, key: "anthropic-ratelimit-unified-7d-utilization") * 100

        var fiveHourResetAt: Date?
        if let resetStr = response.value(forHTTPHeaderField: "anthropic-ratelimit-unified-5h-reset") {
            fiveHourResetAt = parseResetTimestamp(resetStr)
        }

        var sevenDayResetAt: Date?
        if let resetStr = response.value(forHTTPHeaderField: "anthropic-ratelimit-unified-7d-reset") {
            sevenDayResetAt = parseResetTimestamp(resetStr)
        }

        // Sonnet-specific 7d utilization (undocumented but returned by API)
        let sonnetUtil = headerDouble(response, key: "anthropic-ratelimit-unified-7d_sonnet-utilization")
        let sevenDaySonnetUtilization: Double? = sonnetUtil > 0 ? sonnetUtil * 100 : nil

        // If 5h reset is in the past, session has reset
        if let reset = fiveHourResetAt, reset < Date() {
            return QuotaInfo(
                fiveHourUtilization: 0,
                fiveHourResetAt: nil,
                sevenDayUtilization: sevenDayUtil,
                sevenDayResetAt: sevenDayResetAt,
                sevenDayOpusUtilization: nil,
                sevenDaySonnetUtilization: sevenDaySonnetUtilization,
                lastUpdated: Date()
            )
        }

        return QuotaInfo(
            fiveHourUtilization: fiveHourUtil,
            fiveHourResetAt: fiveHourResetAt,
            sevenDayUtilization: sevenDayUtil,
            sevenDayResetAt: sevenDayResetAt,
            sevenDayOpusUtilization: nil,
            sevenDaySonnetUtilization: sevenDaySonnetUtilization,
            lastUpdated: Date()
        )
    }

    private static func headerDouble(_ response: HTTPURLResponse, key: String) -> Double {
        guard let str = response.value(forHTTPHeaderField: key), let val = Double(str) else { return 0 }
        return val
    }

    private static func parseResetTimestamp(_ str: String) -> Date? {
        // Try Unix timestamp first
        if let ts = Double(str) {
            return Date(timeIntervalSince1970: ts)
        }
        // Try ISO 8601
        return ClauditFormatter.parseISO8601(str)
    }
}

// MARK: - OAuth API Provider (existing endpoint)

/// Calls api.anthropic.com/api/oauth/usage with CLI OAuth token.
final class OAuthAPIQuotaProvider: QuotaProvider {
    func fetchQuota() async throws -> QuotaInfo {
        let token = try CredentialReader.readAccessToken()

        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        request.setValue("Claudit/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaError.invalidResponse
        }

        await NetworkLogService.shared.record(
            method: "GET", url: url.absoluteString,
            statusCode: httpResponse.statusCode,
            responseBody: String(data: data.prefix(2000), encoding: .utf8),
            duration: Date().timeIntervalSince(start)
        )

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw QuotaError.tokenExpired
            }
            if httpResponse.statusCode == 429 {
                throw QuotaError.rateLimited
            }
            throw QuotaError.httpError(httpResponse.statusCode)
        }

        return try Self.parseResponse(data)
    }

    static func parseResponse(_ data: Data) throws -> QuotaInfo {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.invalidResponse
        }

        var fiveHourUtilization: Double = 0
        var fiveHourResetAt: Date?
        var sevenDayUtilization: Double = 0
        var sevenDayOpusUtilization: Double?
        var sevenDaySonnetUtilization: Double?

        if let fiveHour = json["five_hour"] as? [String: Any] {
            fiveHourUtilization = parseUtilization(fiveHour)
            if let resetStr = fiveHour["resets_at"] as? String ?? fiveHour["reset_at"] as? String {
                fiveHourResetAt = ClauditFormatter.parseISO8601(resetStr)
            }
        } else if let session = json["session"] as? [String: Any] {
            fiveHourUtilization = parseUtilization(session)
            if let resetStr = session["resets_at"] as? String {
                fiveHourResetAt = ClauditFormatter.parseISO8601(resetStr)
            }
        }

        var sevenDayResetAt: Date?
        if let sevenDay = json["seven_day"] as? [String: Any] {
            sevenDayUtilization = parseUtilization(sevenDay)
            if let resetStr = sevenDay["resets_at"] as? String {
                sevenDayResetAt = ClauditFormatter.parseISO8601(resetStr)
            }
        } else if let weekly = json["weekly"] as? [String: Any] {
            sevenDayUtilization = parseUtilization(weekly)
        }

        if let opus = json["seven_day_opus"] as? [String: Any] {
            sevenDayOpusUtilization = parseUtilization(opus)
        }
        if let sonnet = json["seven_day_sonnet"] as? [String: Any] {
            sevenDaySonnetUtilization = parseUtilization(sonnet)
        }

        return QuotaInfo(
            fiveHourUtilization: fiveHourUtilization,
            fiveHourResetAt: fiveHourResetAt,
            sevenDayUtilization: sevenDayUtilization,
            sevenDayResetAt: sevenDayResetAt,
            sevenDayOpusUtilization: sevenDayOpusUtilization,
            sevenDaySonnetUtilization: sevenDaySonnetUtilization,
            lastUpdated: Date()
        )
    }

    private static func parseUtilization(_ dict: [String: Any]) -> Double {
        if let pct = dict["utilization_pct"] as? Double { return pct }
        if let util = dict["utilization"] as? Double { return util }
        return 0
    }
}

// MARK: - Claude.ai Session Cookie Provider

/// Calls claude.ai/api/organizations/{org}/usage with a session cookie.
final class SessionCookieQuotaProvider: QuotaProvider {
    func fetchQuota() async throws -> QuotaInfo {
        guard let sessionKey = SessionCredentialStore.shared.sessionKey else {
            throw QuotaError.noCredentials
        }
        guard let orgId = SessionCredentialStore.shared.organizationId, !orgId.isEmpty else {
            throw QuotaError.noCredentials
        }

        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
            throw QuotaError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        request.setValue("Claudit/\(appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw QuotaError.sessionExpired
            }
            if httpResponse.statusCode == 429 {
                throw QuotaError.rateLimited
            }
            throw QuotaError.httpError(httpResponse.statusCode)
        }

        // Same JSON format as OAuth API
        return try OAuthAPIQuotaProvider.parseResponse(data)
    }
}

// MARK: - Shared Credential Reader

enum CredentialReader {
    static func readAccessToken() throws -> String {
        if let token = readFromKeychain() {
            return token
        }

        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? (NSHomeDirectory() + "/.claude")
        let credPath = configDir + "/.credentials.json"
        guard let data = FileManager.default.contents(atPath: credPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            throw QuotaError.noCredentials
        }

        if let expiresAt = oauth["expiresAt"] as? TimeInterval {
            let ts = expiresAt > 1e12 ? expiresAt / 1000 : expiresAt
            if Date() > Date(timeIntervalSince1970: ts) {
                throw QuotaError.tokenExpired
            }
        }

        return token
    }

    private static func readFromKeychain() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", "Claude Code-credentials",
            "-a", NSUserName(),
            "-w"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String else {
                return nil
            }

            if let expiresAt = oauth["expiresAt"] as? TimeInterval {
                let ts = expiresAt > 1e12 ? expiresAt / 1000 : expiresAt
                if Date() > Date(timeIntervalSince1970: ts) {
                    return nil
                }
            }

            return token
        } catch {
            return nil
        }
    }
}

// MARK: - Session Credential Store

/// Stores Claude.ai session cookie (in Keychain) and organization ID from browser sign-in.
final class SessionCredentialStore: @unchecked Sendable {
    static let shared = SessionCredentialStore()

    private static let keychainService = "cc.ffitch.Claudit.session"
    private static let keychainAccount = "claudeSessionKey"

    private let lock = NSLock()
    private var _sessionKey: String?
    private var _organizationId: String?
    private var _expiryDate: Date?

    private init() {
        _sessionKey = Self.readKeychain()
        _organizationId = UserDefaults.standard.string(forKey: "claudeOrganizationId")
        if let ts = UserDefaults.standard.object(forKey: "claudeSessionExpiry") as? TimeInterval, ts > 0 {
            _expiryDate = Date(timeIntervalSince1970: ts)
        }
    }

    var sessionKey: String? {
        lock.lock()
        defer { lock.unlock() }
        if let expiry = _expiryDate, expiry < Date() { return nil }
        return _sessionKey
    }

    var organizationId: String? {
        lock.lock()
        defer { lock.unlock() }
        return _organizationId
    }

    var expiryDate: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _expiryDate
    }

    var isConfigured: Bool {
        sessionKey != nil && organizationId != nil
    }

    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry < Date()
    }

    func save(sessionKey: String, organizationId: String, expiryDate: Date?) {
        lock.lock()
        _sessionKey = sessionKey
        _organizationId = organizationId
        _expiryDate = expiryDate
        lock.unlock()

        Self.writeKeychain(sessionKey)
        UserDefaults.standard.set(organizationId, forKey: "claudeOrganizationId")
        if let expiry = expiryDate {
            UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: "claudeSessionExpiry")
        } else {
            UserDefaults.standard.removeObject(forKey: "claudeSessionExpiry")
        }
    }

    func clear() {
        lock.lock()
        _sessionKey = nil
        _organizationId = nil
        _expiryDate = nil
        lock.unlock()

        Self.deleteKeychain()
        UserDefaults.standard.removeObject(forKey: "claudeOrganizationId")
        UserDefaults.standard.removeObject(forKey: "claudeSessionExpiry")
    }

    // MARK: - Keychain

    private static func writeKeychain(_ value: String) {
        deleteKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: Data(value.utf8)
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Fetch organizations from Claude.ai using the stored session key.
    func fetchOrganizations() async throws -> [(id: String, name: String)] {
        guard let key = sessionKey else { throw QuotaError.noCredentials }

        let url = URL(string: "https://claude.ai/api/organizations")!
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw QuotaError.sessionExpired
        }

        guard let orgs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw QuotaError.invalidResponse
        }

        return orgs.compactMap { org in
            guard let id = org["uuid"] as? String,
                  let name = org["name"] as? String else { return nil }
            return (id: id, name: name)
        }
    }
}

// MARK: - Errors

enum QuotaError: LocalizedError, Equatable {
    case noCredentials
    case tokenExpired
    case sessionExpired
    case rateLimited
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Claude credentials found. Run 'claude auth login' or sign in via Settings."
        case .tokenExpired:
            return "Token expired. Re-login with 'claude auth login'."
        case .sessionExpired:
            return "Session expired. Sign in again via Settings."
        case .rateLimited:
            return "Rate limited. Will retry shortly."
        case .invalidResponse:
            return "Invalid API response."
        case .httpError(let code):
            return "HTTP \(code)"
        }
    }
}

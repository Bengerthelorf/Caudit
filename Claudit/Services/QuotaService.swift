import Foundation

final class QuotaService: Sendable {
    private static let maxRetries = 3
    private static let retryBaseDelay: TimeInterval = 5.0
    private static let retryMaxDelay: TimeInterval = 30.0

    func fetchQuota() async throws -> QuotaInfo {
        let token = try readAccessToken()

        for attempt in 0..<Self.maxRetries {
            do {
                return try await performRequest(token: token)
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

    private func performRequest(token: String) async throws -> QuotaInfo {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        request.setValue("Claudit/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw QuotaError.tokenExpired
            }
            if httpResponse.statusCode == 429 {
                throw QuotaError.rateLimited
            }
            throw QuotaError.httpError(httpResponse.statusCode)
        }

        return try parseQuotaResponse(data)
    }

    private func readAccessToken() throws -> String {
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

    private func readFromKeychain() -> String? {
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

    private func parseQuotaResponse(_ data: Data) throws -> QuotaInfo {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.invalidResponse
        }

        var fiveHourUtilization: Double = 0
        var fiveHourResetAt: Date?
        var sevenDayUtilization: Double = 0
        var sevenDayOpusUtilization: Double?
        var sevenDaySonnetUtilization: Double?

        if let fiveHour = json["five_hour"] as? [String: Any] {
            fiveHourUtilization = Self.parseUtilization(fiveHour)
            if let resetStr = fiveHour["resets_at"] as? String ?? fiveHour["reset_at"] as? String {
                fiveHourResetAt = ClauditFormatter.parseISO8601(resetStr)
            }
        } else if let session = json["session"] as? [String: Any] {
            fiveHourUtilization = Self.parseUtilization(session)
            if let resetStr = session["resets_at"] as? String {
                fiveHourResetAt = ClauditFormatter.parseISO8601(resetStr)
            }
        }

        var sevenDayResetAt: Date?
        if let sevenDay = json["seven_day"] as? [String: Any] {
            sevenDayUtilization = Self.parseUtilization(sevenDay)
            if let resetStr = sevenDay["resets_at"] as? String {
                sevenDayResetAt = ClauditFormatter.parseISO8601(resetStr)
            }
        } else if let weekly = json["weekly"] as? [String: Any] {
            sevenDayUtilization = Self.parseUtilization(weekly)
        }

        if let opus = json["seven_day_opus"] as? [String: Any] {
            sevenDayOpusUtilization = Self.parseUtilization(opus)
        }
        if let sonnet = json["seven_day_sonnet"] as? [String: Any] {
            sevenDaySonnetUtilization = Self.parseUtilization(sonnet)
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
        if let pct = dict["utilization_pct"] as? Double {
            return pct
        }
        if let util = dict["utilization"] as? Double {
            return util
        }
        return 0
    }

}

enum QuotaError: LocalizedError, Equatable {
    case noCredentials
    case tokenExpired
    case rateLimited
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Claude credentials found. Run 'claude auth login' first."
        case .tokenExpired:
            return "Token expired. Re-login with 'claude auth login'."
        case .rateLimited:
            return "Rate limited. Will retry shortly."
        case .invalidResponse:
            return "Invalid API response."
        case .httpError(let code):
            return "HTTP \(code)"
        }
    }
}

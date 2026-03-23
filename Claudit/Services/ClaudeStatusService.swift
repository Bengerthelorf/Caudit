import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "ClaudeStatus")

/// Fetches Claude system status from the Atlassian Statuspage API.
final class ClaudeStatusService: Sendable {
    private let statusURL = URL(string: "https://status.anthropic.com/api/v2/status.json")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchStatus() async throws -> ClaudeStatus {
        let (data, _) = try await session.data(from: statusURL)
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> ClaudeStatus {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let statusDict = json?["status"] as? [String: Any] else {
            throw ClaudeStatusError.invalidResponse
        }

        let indicatorString = statusDict["indicator"] as? String ?? "unknown"
        let indicator = ClaudeStatus.Indicator(rawValue: indicatorString) ?? .unknown
        let description = statusDict["description"] as? String ?? indicator.label

        var updatedAt: Date?
        if let pageDict = json?["page"] as? [String: Any],
           let updatedAtString = pageDict["updated_at"] as? String {
            updatedAt = ClauditFormatter.parseISO8601(updatedAtString)
        }

        return ClaudeStatus(indicator: indicator, description: description, updatedAt: updatedAt)
    }
}

enum ClaudeStatusError: Error {
    case invalidResponse
}

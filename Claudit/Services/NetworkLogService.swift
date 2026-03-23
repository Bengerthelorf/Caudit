import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "NetworkLog")

/// Records API requests and responses in a circular buffer for debugging.
@MainActor
final class NetworkLogService {
    static let shared = NetworkLogService()

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let method: String
        let url: String
        let statusCode: Int?
        let requestHeaders: [String: String]
        let responseHeaders: [String: String]
        let responseBody: String?
        let error: String?
        let duration: TimeInterval
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 100

    private init() {}

    func record(
        method: String,
        url: String,
        statusCode: Int?,
        requestHeaders: [String: String] = [:],
        responseHeaders: [String: String] = [:],
        responseBody: String? = nil,
        error: String? = nil,
        duration: TimeInterval
    ) {
        let entry = Entry(
            timestamp: Date(),
            method: method,
            url: url,
            statusCode: statusCode,
            requestHeaders: requestHeaders,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            error: error,
            duration: duration
        )

        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        logger.debug("[\(method)] \(url) → \(statusCode ?? 0) (\(String(format: "%.0f", duration * 1000))ms)")
    }

    func clear() {
        entries.removeAll()
    }
}

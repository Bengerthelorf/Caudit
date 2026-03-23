import Foundation

struct SessionInfo: Identifiable, Sendable, Hashable {
    var id: String { sessionId }
    let sessionId: String
    let slug: String
    let project: String
    let projectDir: String
    let source: String
    var firstTimestamp: Date
    var lastTimestamp: Date
    var messageCount: Int = 0
    var totalTokens: Int = 0
    var totalCost: Double = 0

    static func == (lhs: SessionInfo, rhs: SessionInfo) -> Bool {
        lhs.sessionId == rhs.sessionId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sessionId)
    }

    var duration: TimeInterval {
        lastTimestamp.timeIntervalSince(firstTimestamp)
    }

    var displayName: String {
        guard !slug.isEmpty else { return sessionId.prefix(8).description }
        return slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

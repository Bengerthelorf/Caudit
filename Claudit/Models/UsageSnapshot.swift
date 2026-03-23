import Foundation

enum SnapshotType: String, Codable, Sendable {
    case session   // 5h window
    case weekly    // 7d window
}

struct UsageSnapshot: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let type: SnapshotType
    let percentage: Double
    let tokensUsed: Int?

    init(timestamp: Date = Date(), type: SnapshotType, percentage: Double, tokensUsed: Int? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.type = type
        self.percentage = percentage
        self.tokensUsed = tokensUsed
    }
}

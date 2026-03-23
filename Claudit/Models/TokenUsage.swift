import Foundation

struct AggregatedUsage: Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var totalCost: Double = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    mutating func add(_ other: AggregatedUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheCreationTokens += other.cacheCreationTokens
        totalCost += other.totalCost
    }
}

struct ModelUsageEntry: Identifiable, Sendable {
    var id: String { model }
    let model: String
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var totalCost: Double = 0

    var cacheTokens: Int {
        cacheReadTokens + cacheCreationTokens
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheTokens
    }
}

struct UsageRecord: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let model: String
    let timestamp: Date
    let cost: Double
    let project: String
    let source: String
    let sessionId: String
    let slug: String
    let toolCalls: [String]
    let projectDir: String
}

struct ToolUsageEntry: Identifiable, Sendable {
    var id: String { name }
    let name: String
    var usageCount: Int = 0
}

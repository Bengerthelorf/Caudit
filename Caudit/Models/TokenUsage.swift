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

struct SessionInfo: Identifiable, Sendable {
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

    var duration: TimeInterval {
        lastTimestamp.timeIntervalSince(firstTimestamp)
    }

    var displayName: String {
        guard !slug.isEmpty else { return sessionId.prefix(8).description }
        return slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

struct ParseResult: Sendable {
    let today: AggregatedUsage
    let month: AggregatedUsage
    let allTime: AggregatedUsage
    let modelBreakdown: [ModelUsageEntry]
    let dailyHistory: [DailyUsage]
    let projectBreakdown: [ProjectUsage]
    let sessionBreakdown: [SessionInfo]
    let toolBreakdown: [ToolUsageEntry]
    let allTimeDailyHistory: [DailyUsage]
    let todayHourlyHistory: [DailyUsage]
    let dayHourlyBreakdown: [DayHourlyBreakdown]
}

struct DailyUsage: Identifiable, Sendable {
    var id: String { dateString }
    let date: Date
    let dateString: String
    var totalCost: Double = 0
    var totalTokens: Int = 0
    var costBySource: [String: Double] = [:]
}

struct ProjectUsage: Identifiable, Sendable {
    var id: String { project }
    let project: String
    var totalCost: Double = 0
    var totalTokens: Int = 0
    var sessionCount: Int = 0
    var lastActive: Date = .distantPast
    var source: String = "Local"
}

struct DayHourlyBreakdown: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    var slotCosts: [Double]  // 6 four-hour slots (0-3, 4-7, 8-11, 12-15, 16-19, 20-23)

    var totalCost: Double { slotCosts.reduce(0, +) }
}

struct QuotaInfo: Sendable {
    let fiveHourUtilization: Double
    let fiveHourResetAt: Date?
    let sevenDayUtilization: Double
    let sevenDayResetAt: Date?
    let sevenDayOpusUtilization: Double?
    let sevenDaySonnetUtilization: Double?
    let lastUpdated: Date

    var fiveHourTimeRemaining: TimeInterval? {
        guard let resetAt = fiveHourResetAt else { return nil }
        let remaining = resetAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    var sevenDayTimeRemaining: TimeInterval? {
        guard let resetAt = sevenDayResetAt else { return nil }
        let remaining = resetAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }
}

// MARK: - Dashboard Filter

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "Month"
    case allTime = "All Time"

    var id: String { rawValue }

    var filterStart: Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        switch self {
        case .today: return startOfToday
        case .week: return calendar.date(byAdding: .day, value: -6, to: startOfToday)!
        case .month: return calendar.date(byAdding: .day, value: -30, to: startOfToday)!
        case .allTime: return .distantPast
        }
    }
}

struct DashboardFilter: Equatable {
    var timeRange: TimeRange = .month
    var selectedSources: Set<String> = []
}

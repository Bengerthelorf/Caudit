import Foundation

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
    var slotCosts: [Double]

    var totalCost: Double { slotCosts.reduce(0, +) }
}

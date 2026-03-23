import SwiftUI

// MARK: - Activity

struct ActivityPage: View {
    @Environment(AppState.self) private var appState

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM/dd"; return f
    }()

    private var filterStart: Date {
        appState.dashboardFilter.timeRange.filterStart
    }

    private var sessionDurations: [TimeInterval] {
        appState.sessionBreakdown
            .map(\.duration)
            .filter { $0 > 0 }
    }

    private var avgDuration: TimeInterval {
        guard !sessionDurations.isEmpty else { return 0 }
        return sessionDurations.reduce(0, +) / Double(sessionDurations.count)
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading activity data…")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    UnifiedFilterBar(showTimeRange: true)

                    SectionHeader(title: "Activity", icon: "chart.dots.scatter")

                    switch appState.dashboardFilter.timeRange {
                    case .today:
                        TodayHeatmap(hourlyData: appState.todayHourlyHistory)
                    case .week:
                        WeekHeatmap(data: weekHeatmapDays)
                    case .month:
                        MonthHeatmap(dailyData: monthDailyData)
                    case .allTime:
                        GitHubCalendarHeatmap(
                            dailyHistory: appState.allTimeDailyHistory
                        )
                    }

                    if !sessionDurations.isEmpty {
                        SectionHeader(title: "Session Duration", icon: "clock")

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            StatCard(
                                label: "Total Sessions",
                                value: "\(sessionDurations.count)",
                                color: Palette.blue
                            )
                            StatCard(
                                label: "Avg Duration",
                                value: ClauditFormatter.duration(avgDuration),
                                color: Palette.lavender
                            )
                            StatCard(
                                label: "Longest",
                                value: ClauditFormatter.duration(sessionDurations.max() ?? 0),
                                color: Palette.terracotta
                            )
                            StatCard(
                                label: "Shortest",
                                value: ClauditFormatter.duration(sessionDurations.min() ?? 0),
                                color: Palette.sage
                            )
                        }
                    }

                    SectionHeader(title: "Cost Trend", icon: "chart.bar")

                    TrendChart(
                        dailyHistory: trendData,
                        availableSources: appState.availableSources,
                        granularity: appState.dashboardFilter.timeRange == .today ? .hourly : .daily
                    )
                }
                .padding(20)
            }
        }
    }

    private var weekHeatmapDays: [DayHourlyBreakdown] {
        let calendar = Calendar.current
        let start = TimeRange.week.filterStart
        let endOfToday = calendar.startOfDay(for: Date())

        var lookup: [Int: DayHourlyBreakdown] = [:]
        for entry in appState.dayHourlyBreakdown where entry.date >= start {
            if let jd = calendar.ordinality(of: .day, in: .era, for: entry.date) {
                lookup[jd] = entry
            }
        }

        var result: [DayHourlyBreakdown] = []
        var current = start
        while current <= endOfToday {
            let jd = calendar.ordinality(of: .day, in: .era, for: current) ?? 0
            if let existing = lookup[jd] {
                result.append(existing)
            } else {
                result.append(DayHourlyBreakdown(date: current, slotCosts: Array(repeating: 0, count: 4)))
            }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        return result
    }

    private var monthDailyData: [DailyUsage] {
        let calendar = Calendar.current
        let start = TimeRange.month.filterStart
        let endOfToday = calendar.startOfDay(for: Date())

        var lookup: [String: DailyUsage] = [:]
        for day in appState.allTimeDailyHistory where day.date >= start {
            lookup[day.dateString] = day
        }

        var result: [DailyUsage] = []
        var current = start
        while current <= endOfToday {
            let key = Self.dayFmt.string(from: current)
            result.append(lookup[key] ?? DailyUsage(date: current, dateString: key))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    private var trendData: [DailyUsage] {
        if appState.dashboardFilter.timeRange == .today {
            return appState.todayHourlyHistory
        }
        return appState.allTimeDailyHistory.filter { $0.date >= filterStart }
    }
}

// MARK: - Today Heatmap

struct TodayHeatmap: View {
    let hourlyData: [DailyUsage]
    @State private var hoveredInfo: String?

    var body: some View {
        let maxCost = hourlyData.map(\.totalCost).max() ?? 0

        GroupBox {
            if hourlyData.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 2) {
                        ForEach(0..<24, id: \.self) { hour in
                            let cost = hour < hourlyData.count ? hourlyData[hour].totalCost : 0
                            let intensity = maxCost > 0 ? cost / maxCost : 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(heatmapColor(intensity, hasData: cost > 0))
                                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                                .onHover { hovering in
                                    hoveredInfo = hovering ? "\(hour):00–\(hour + 1):00  \(ClauditFormatter.costDetail(cost))" : nil
                                }
                        }
                    }

                    HStack(spacing: 2) {
                        ForEach(0..<24, id: \.self) { hour in
                            Group {
                                if hour % 3 == 0 {
                                    Text("\(hour)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    HeatmapFooter(hoveredInfo: hoveredInfo)
                }
            }
        }
    }
}

// MARK: - Week Heatmap

struct WeekHeatmap: View {
    let data: [DayHourlyBreakdown]

    private static let timeLabels = ["0:00", "6:00", "12:00", "18:00"]
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "E\nM/d"; return f
    }()
    @State private var hoveredInfo: String?

    private var maxCost: Double {
        data.flatMap(\.slotCosts).max() ?? 0
    }

    var body: some View {
        GroupBox {
            if data.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Color.clear.frame(width: 40, height: 1)
                        ForEach(data) { day in
                            Text(Self.dayFmt.string(from: day.date))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    ForEach(0..<4, id: \.self) { slot in
                        HStack(spacing: 2) {
                            Text(Self.timeLabels[slot])
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .leading)

                            ForEach(data) { day in
                                let cost = day.slotCosts[slot]
                                let intensity = maxCost > 0 ? cost / maxCost : 0
                                let label = Self.dayFmt.string(from: day.date).replacingOccurrences(of: "\n", with: " ")
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(heatmapColor(intensity, hasData: cost > 0))
                                    .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                                    .onHover { hovering in
                                        hoveredInfo = hovering ? "\(label) \(Self.timeLabels[slot])  \(ClauditFormatter.costDetail(cost))" : nil
                                    }
                            }
                        }
                    }

                    HeatmapFooter(hoveredInfo: hoveredInfo)
                }
            }
        }
    }
}

// MARK: - Month Heatmap

struct MonthHeatmap: View {
    let dailyData: [DailyUsage]
    private let rows = 5
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    @State private var hoveredInfo: String?

    private var columns: Int {
        (dailyData.count + rows - 1) / rows
    }

    var body: some View {
        let maxCost = dailyData.map(\.totalCost).max() ?? 0

        GroupBox {
            if dailyData.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(0..<columns, id: \.self) { col in
                            let i = col * rows
                            if i < dailyData.count {
                                Text(Self.dateFmt.string(from: dailyData[i].date))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    HStack(spacing: 2) {
                        ForEach(0..<columns, id: \.self) { col in
                            VStack(spacing: 2) {
                                ForEach(0..<rows, id: \.self) { row in
                                    let i = col * rows + row
                                    if i < dailyData.count {
                                        let cost = dailyData[i].totalCost
                                        let intensity = maxCost > 0 ? cost / maxCost : 0
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(heatmapColor(intensity, hasData: cost > 0))
                                            .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                                            .onHover { hovering in
                                                hoveredInfo = hovering ? "\(dailyData[i].dateString)  \(ClauditFormatter.costDetail(cost))" : nil
                                            }
                                    } else {
                                        Color.clear.frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                                    }
                                }
                            }
                        }
                    }

                    HeatmapFooter(hoveredInfo: hoveredInfo)
                }
            }
        }
    }
}

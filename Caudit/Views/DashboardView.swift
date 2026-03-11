import SwiftUI
import Charts

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case activity = "Activity"
    case sessions = "Sessions"
    case projects = "Projects"
    case models = "Models"
    case tools = "Tools"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .activity: "chart.dots.scatter"
        case .sessions: "bubble.left.and.bubble.right"
        case .projects: "folder"
        case .models: "cpu"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            List(DashboardTab.allCases, selection: $state.selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
            .navigationTitle("Caudit")
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            if let session = appState.selectedSessionForDetail {
                SessionDetailView(session: session)
            } else {
                switch appState.selectedTab {
                case .overview, .none:
                    OverviewPage()
                        .navigationTitle("Overview")
                case .activity:
                    ActivityPage()
                        .navigationTitle("Activity")
                case .sessions:
                    SessionsPage()
                        .navigationTitle("Sessions")
                case .projects:
                    ProjectsPage()
                        .navigationTitle("Projects")
                case .models:
                    ModelsPage()
                        .navigationTitle("Models")
                case .tools:
                    ToolsPage()
                        .navigationTitle("Tools")
                }
            }
        }
        .onChange(of: appState.selectedTab) { _, _ in
            appState.selectedSessionForDetail = nil
        }
    }
}

// MARK: - Source Colors

enum SourceColor {
    static let localColor: Color = .init(red: 0.35, green: 0.60, blue: 1.0)  // Soft blue
    private static let remotePalette: [Color] = [
        .init(red: 1.0, green: 0.62, blue: 0.30),  // Warm orange
        .init(red: 0.40, green: 0.82, blue: 0.70),  // Teal
        .init(red: 0.95, green: 0.55, blue: 0.60),  // Coral
        .init(red: 0.60, green: 0.75, blue: 0.95),  // Light blue
        .init(red: 0.85, green: 0.70, blue: 0.95),  // Lavender
        .init(red: 0.95, green: 0.80, blue: 0.45),  // Gold
    ]

    static func color(for source: String, allSources: [String]) -> Color {
        if source == "Local" { return localColor }
        let remotes = allSources.filter { $0 != "Local" }.sorted()
        guard let idx = remotes.firstIndex(of: source) else { return .gray }
        let base = remotePalette[idx % remotePalette.count]
        let cycle = idx / remotePalette.count
        return cycle == 0 ? base : base.opacity(1.0 - Double(cycle) * 0.25)
    }
}

// MARK: - Filter Bar

private struct FilterBar: View {
    @Environment(AppState.self) private var appState
    var showTimeRange: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if appState.availableSources.count > 1 {
                ForEach(appState.availableSources, id: \.self) { source in
                    SourceChip(
                        name: source,
                        color: SourceColor.color(for: source, allSources: appState.availableSources),
                        isSelected: isSourceVisible(source)
                    ) {
                        appState.toggleSource(source)
                    }
                }
            }

            Spacer()

            if showTimeRange {
                @Bindable var state = appState
                Picker("Period", selection: $state.dashboardFilter.timeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
            }
        }
    }

    private func isSourceVisible(_ source: String) -> Bool {
        appState.dashboardFilter.selectedSources.isEmpty
            || appState.dashboardFilter.selectedSources.contains(source)
    }
}

private struct SourceChip: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? color : color.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.1) : .clear, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Loading Placeholder

private struct LoadingPlaceholder: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Overview

private struct OverviewPage: View {
    @Environment(AppState.self) private var appState

    private var hasSources: Bool { appState.availableSources.count > 1 }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading usage data…")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hasSources {
                        FilterBar()
                    }

                    SectionHeader(title: "Usage Summary", icon: "dollarsign.circle")

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        StatCard(
                            label: "Today",
                            value: CauditFormatter.costDetail(appState.todayUsage.totalCost),
                            detail: CauditFormatter.tokensWithUnit(appState.todayUsage.totalTokens),
                            color: .blue
                        )
                        StatCard(
                            label: "This Month",
                            value: CauditFormatter.costDetail(appState.monthUsage.totalCost),
                            detail: CauditFormatter.tokensWithUnit(appState.monthUsage.totalTokens),
                            color: .purple
                        )
                        StatCard(
                            label: "All Time",
                            value: CauditFormatter.costDetail(appState.allTimeUsage.totalCost),
                            detail: CauditFormatter.tokensWithUnit(appState.allTimeUsage.totalTokens),
                            color: .green
                        )
                        if let rate = appState.burnRate {
                            StatCard(
                                label: "Burn Rate",
                                value: CauditFormatter.costDetail(rate),
                                detail: "per day · ~\(CauditFormatter.cost(rate * 30))/mo",
                                color: .orange
                            )
                        }
                    }

                    if let quota = appState.quotaInfo {
                        SectionHeader(title: "Quota", icon: "gauge.with.dots.needle.50percent")

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            StatCard(label: "5h Window", value: "\(Int(quota.fiveHourUtilization))%", color: quotaColor(quota.fiveHourUtilization))
                            StatCard(label: "7-Day", value: "\(Int(quota.sevenDayUtilization))%", color: quotaColor(quota.sevenDayUtilization))
                            if let opus = quota.sevenDayOpusUtilization {
                                StatCard(label: "Opus (7d)", value: "\(Int(opus))%", color: quotaColor(opus))
                            }
                            if let sonnet = quota.sevenDaySonnetUtilization {
                                StatCard(label: "Sonnet (7d)", value: "\(Int(sonnet))%", color: quotaColor(sonnet))
                            }
                        }
                    }

                    SectionHeader(title: "7-Day Trend", icon: "chart.bar")

                    TrendChart(
                        dailyHistory: appState.dailyHistory,
                        availableSources: appState.availableSources
                    )

                    if !appState.allTimeDailyHistory.isEmpty {
                        SectionHeader(title: "All Time", icon: "chart.dots.scatter")

                        GitHubCalendarHeatmap(dailyHistory: appState.allTimeDailyHistory)
                    }
                }
                .padding(20)
            }
        }
    }

    private func quotaColor(_ pct: Double) -> Color {
        if pct < 50 { return .green }
        if pct < 80 { return .orange }
        return .red
    }
}

// MARK: - GitHub Calendar Heatmap

private struct CalendarCell {
    let date: Date
    let label: String
    let cost: Double
    let hasData: Bool
}

private struct GitHubCalendarHeatmap: View {
    let dailyHistory: [DailyUsage]
    var minWeeks: Int = 52

    private static let greens: [Color] = [
        Color(red: 0.92, green: 0.93, blue: 0.90),
        Color(red: 0.61, green: 0.91, blue: 0.66),
        Color(red: 0.25, green: 0.77, blue: 0.33),
        Color(red: 0.19, green: 0.56, blue: 0.25),
        Color(red: 0.13, green: 0.37, blue: 0.17),
    ]

    var body: some View {
        let grid = buildGrid()
        let maxCost = dailyHistory.map(\.totalCost).max() ?? 0

        GroupBox {
            if grid.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            monthLabelsRow(grid: grid)

                            HStack(spacing: 2) {
                                ForEach(grid.indices, id: \.self) { weekIdx in
                                    VStack(spacing: 2) {
                                        ForEach(0..<7, id: \.self) { dayIdx in
                                            cellView(grid[weekIdx][dayIdx], maxCost: maxCost)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                    .defaultScrollAnchor(.trailing)

                    HStack(spacing: 4) {
                        Spacer()
                        Text("Less")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        ForEach(0..<5, id: \.self) { level in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(level == 0 ? Self.greens[0].opacity(0.5) : Self.greens[level])
                                .frame(width: 10, height: 10)
                        }
                        Text("More")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func monthLabelsRow(grid: [[CalendarCell]]) -> some View {
        let labels = computeMonthLabels(grid: grid)

        HStack(spacing: 2) {
            ForEach(grid.indices, id: \.self) { weekIdx in
                if let label = labels[weekIdx] {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: 12, alignment: .leading)
                } else {
                    Color.clear.frame(width: 12, height: 10)
                }
            }
        }
    }

    private func computeMonthLabels(grid: [[CalendarCell]]) -> [Int: String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var labels: [Int: String] = [:]
        var lastMonth = -1

        for (idx, week) in grid.enumerated() {
            let month = calendar.component(.month, from: week[0].date)
            if month != lastMonth {
                if idx > 0 { labels[idx] = formatter.string(from: week[0].date) }
                lastMonth = month
            }
        }

        return labels
    }

    private func cellView(_ cell: CalendarCell, maxCost: Double) -> some View {
        let color: Color
        if !cell.hasData {
            color = Self.greens[0].opacity(0.3)
        } else {
            let intensity = maxCost > 0 ? cell.cost / maxCost : 0
            if intensity == 0 {
                color = Self.greens[0].opacity(0.5)
            } else if intensity < 0.25 {
                color = Self.greens[1]
            } else if intensity < 0.50 {
                color = Self.greens[2]
            } else if intensity < 0.75 {
                color = Self.greens[3]
            } else {
                color = Self.greens[4]
            }
        }

        return RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 12, height: 12)
            .help(cell.hasData
                ? "\(cell.label): \(CauditFormatter.costDetail(cell.cost))"
                : cell.label)
    }

    private func buildGrid() -> [[CalendarCell]] {
        guard !dailyHistory.isEmpty else { return [] }

        let calendar = Calendar.current
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM d, yyyy"

        // Build lookup: julian day → cost
        var costByJulian: [Int: Double] = [:]
        for day in dailyHistory {
            if let jd = calendar.ordinality(of: .day, in: .era, for: day.date) {
                costByJulian[jd, default: 0] += day.totalCost
            }
        }

        let lastDate = dailyHistory.last!.date

        // Pad end to Saturday
        let endWeekday = calendar.component(.weekday, from: lastDate)
        let endDate = calendar.date(byAdding: .day, value: 7 - endWeekday, to: lastDate)!

        // Optionally pad to minimum weeks for scrollable range
        let firstDate = dailyHistory.first!.date
        let dataStart: Date
        if minWeeks > 0 {
            let minStart = calendar.date(byAdding: .weekOfYear, value: -(minWeeks - 1), to: endDate)!
            dataStart = min(firstDate, minStart)
        } else {
            dataStart = firstDate
        }

        // Pad start to Sunday
        let startWeekday = calendar.component(.weekday, from: dataStart)
        let startDate = calendar.date(byAdding: .day, value: -(startWeekday - 1), to: dataStart)!

        var grid: [[CalendarCell]] = []
        var current = startDate

        while current <= endDate {
            var week: [CalendarCell] = []
            for _ in 0..<7 {
                let jd = calendar.ordinality(of: .day, in: .era, for: current) ?? 0
                let cost = costByJulian[jd]
                week.append(CalendarCell(
                    date: current,
                    label: labelFormatter.string(from: current),
                    cost: cost ?? 0,
                    hasData: cost != nil
                ))
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }
            grid.append(week)
        }

        return grid
    }
}

// MARK: - Trend Chart (reusable)

enum ChartGranularity {
    case daily
    case hourly
}

private struct DateChartEntry: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(source)" }
    let date: Date
    let source: String
    let cost: Double
}

private struct TrendChart: View {
    let dailyHistory: [DailyUsage]
    let availableSources: [String]
    var granularity: ChartGranularity = .daily

    private var dateEntries: [DateChartEntry] {
        dailyHistory.flatMap { day in
            availableSources.compactMap { source in
                guard let cost = day.costBySource[source], cost > 0 else { return nil }
                return DateChartEntry(date: day.date, source: source, cost: cost)
            }
        }
    }

    private var hasSources: Bool { availableSources.count > 1 }

    private var calendarUnit: Calendar.Component {
        granularity == .hourly ? .hour : .day
    }

    var body: some View {
        GroupBox {
            if dailyHistory.isEmpty || (hasSources && dateEntries.isEmpty) {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if hasSources {
                Chart(dateEntries) { entry in
                    BarMark(
                        x: .value("Time", entry.date, unit: calendarUnit),
                        y: .value("Cost", entry.cost)
                    )
                    .foregroundStyle(by: .value("Source", entry.source))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale(
                    domain: availableSources,
                    range: availableSources.map {
                        SourceColor.color(for: $0, allSources: availableSources)
                    }
                )
                .chartYAxis { costAxisMarks }
                .chartXAxis { xAxisMarks }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 220)
                .padding(.top, 4)
            } else {
                Chart(dailyHistory) { day in
                    BarMark(
                        x: .value("Time", day.date, unit: calendarUnit),
                        y: .value("Cost", day.totalCost)
                    )
                    .foregroundStyle(.blue.gradient)
                    .cornerRadius(3)
                }
                .chartYAxis { costAxisMarks }
                .chartXAxis { xAxisMarks }
                .frame(height: 200)
                .padding(.top, 4)
            }
        }
    }

    private var costAxisMarks: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisValueLabel {
                if let cost = value.as(Double.self) {
                    Text(CauditFormatter.cost(cost))
                        .font(.caption)
                }
            }
            AxisGridLine()
        }
    }

    @AxisContentBuilder
    private var xAxisMarks: some AxisContent {
        if granularity == .hourly {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.hour())
                AxisGridLine()
            }
        } else {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                AxisGridLine()
            }
        }
    }

    private var xAxisStride: Int {
        let count = dailyHistory.count
        if count <= 7 { return 1 }
        if count <= 31 { return 5 }
        if count <= 90 { return 14 }
        return 30
    }
}

// MARK: - Activity

private struct ActivityPage: View {
    @Environment(AppState.self) private var appState

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
                    FilterBar(showTimeRange: true)

                    SectionHeader(title: "Activity", icon: "chart.dots.scatter")

                    GitHubCalendarHeatmap(
                        dailyHistory: heatmapData,
                        minWeeks: appState.dashboardFilter.timeRange == .allTime ? 52 : 0
                    )

                    if !sessionDurations.isEmpty {
                        SectionHeader(title: "Session Duration", icon: "clock")

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            StatCard(
                                label: "Total Sessions",
                                value: "\(sessionDurations.count)",
                                color: .blue
                            )
                            StatCard(
                                label: "Avg Duration",
                                value: CauditFormatter.duration(avgDuration),
                                color: .purple
                            )
                            StatCard(
                                label: "Longest",
                                value: CauditFormatter.duration(sessionDurations.max() ?? 0),
                                color: .orange
                            )
                            StatCard(
                                label: "Shortest",
                                value: CauditFormatter.duration(sessionDurations.min() ?? 0),
                                color: .green
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

    private var heatmapData: [DailyUsage] {
        switch appState.dashboardFilter.timeRange {
        case .today:
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())
            return appState.allTimeDailyHistory.filter { calendar.isDate($0.date, inSameDayAs: todayStart) }
        case .week:
            return appState.dailyHistory
        case .month:
            let calendar = Calendar.current
            let now = Date()
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return appState.allTimeDailyHistory.filter { $0.date >= startOfMonth }
        case .allTime:
            return appState.allTimeDailyHistory
        }
    }

    private var trendData: [DailyUsage] {
        if appState.dashboardFilter.timeRange == .today {
            return appState.todayHourlyHistory
        }
        return heatmapData
    }
}

// MARK: - Sessions

private struct SessionsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\SessionInfo.lastTimestamp, order: .reverse)]
    @State private var selectedSessionId: SessionInfo.ID?

    private var filteredSessions: [SessionInfo] {
        var sessions = appState.sessionBreakdown
        if let project = appState.projectFilter {
            sessions = sessions.filter { $0.project == project }
        }
        return sessions.sorted(using: sortOrder)
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading sessions…")
        } else if appState.sessionBreakdown.isEmpty {
            ContentUnavailableView("No Sessions", systemImage: "bubble.left.and.bubble.right", description: Text("Session data will appear here once usage is recorded."))
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if let project = appState.projectFilter {
                        Button {
                            appState.projectFilter = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text(project)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    FilterBar(showTimeRange: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Table(filteredSessions, selection: $selectedSessionId, sortOrder: $sortOrder) {
                    TableColumn("Session", value: \.slug) { session in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(SourceColor.color(for: session.source, allSources: appState.availableSources))
                                .frame(width: 8, height: 8)
                            Text(session.displayName)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Project", value: \.project) { session in
                        Text(session.project)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(ideal: 120)

                    TableColumn("Duration", value: \.duration) { session in
                        Text(CauditFormatter.duration(session.duration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Calls", value: \.messageCount) { session in
                        Text("\(session.messageCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 60)

                    TableColumn("Tokens", value: \.totalTokens) { session in
                        Text(CauditFormatter.tokensWithUnit(session.totalTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 90)

                    TableColumn("Cost", value: \.totalCost) { session in
                        Text(CauditFormatter.costDetail(session.totalCost))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                    .width(ideal: 80)

                    TableColumn("Last Active", value: \.lastTimestamp) { session in
                        Text(session.lastTimestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 120)
                }
                .onChange(of: selectedSessionId) { _, newValue in
                    // Double-click detected via selection + keyboard enter, or use contextual menu
                }
                .onKeyPress(.return) {
                    if let id = selectedSessionId,
                       let session = filteredSessions.first(where: { $0.id == id }) {
                        appState.selectedSessionForDetail = session
                        return .handled
                    }
                    return .ignored
                }
                .contextMenu(forSelectionType: SessionInfo.ID.self) { ids in
                    if let id = ids.first,
                       let session = filteredSessions.first(where: { $0.id == id }) {
                        Button("View Conversation") {
                            appState.selectedSessionForDetail = session
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first,
                       let session = filteredSessions.first(where: { $0.id == id }) {
                        appState.selectedSessionForDetail = session
                    }
                }
            }
        }
    }
}

// MARK: - Projects

private struct ProjectsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\ProjectUsage.totalCost, order: .reverse)]
    @State private var selectedProjectId: ProjectUsage.ID?

    private var sortedProjects: [ProjectUsage] {
        appState.projectBreakdown.sorted(using: sortOrder)
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading projects…")
        } else if appState.projectBreakdown.isEmpty {
            ContentUnavailableView("No Projects", systemImage: "folder", description: Text("Project data will appear here once usage is recorded."))
        } else {
            VStack(spacing: 0) {
                FilterBar(showTimeRange: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Table(sortedProjects, selection: $selectedProjectId, sortOrder: $sortOrder) {
                    TableColumn("Project", value: \.project) { project in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(SourceColor.color(for: project.source, allSources: appState.availableSources))
                                .frame(width: 8, height: 8)
                            Text(project.project)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 150, ideal: 250)

                    TableColumn("Source", value: \.source) { project in
                        Text(project.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Tokens", value: \.totalTokens) { project in
                        Text(CauditFormatter.tokensWithUnit(project.totalTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 90)

                    TableColumn("Cost", value: \.totalCost) { project in
                        Text(CauditFormatter.costDetail(project.totalCost))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                    .width(ideal: 80)

                    TableColumn("Last Active", value: \.lastActive) { project in
                        Text(project.lastActive.formatted(.dateTime.month(.abbreviated).day()))
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 90)
                }
                .contextMenu(forSelectionType: ProjectUsage.ID.self) { ids in
                    if let id = ids.first,
                       let project = sortedProjects.first(where: { $0.id == id }) {
                        Button("View Sessions") {
                            appState.projectFilter = project.project
                            appState.selectedTab = .sessions
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first,
                       let project = sortedProjects.first(where: { $0.id == id }) {
                        appState.projectFilter = project.project
                        appState.selectedTab = .sessions
                    }
                }
            }
        }
    }
}

// MARK: - Unified Filter Bar (Menu-based)

private struct UnifiedFilterBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 8) {
            if appState.availableSources.count > 1 {
                Menu {
                    Button {
                        appState.dashboardFilter.selectedSources = []
                    } label: {
                        HStack {
                            Text("All Devices")
                            if appState.dashboardFilter.selectedSources.isEmpty {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(appState.availableSources, id: \.self) { source in
                        Button {
                            selectSingleSource(source)
                        } label: {
                            HStack {
                                Text(source)
                                if isSingleSourceSelected(source) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "desktopcomputer")
                        Text(deviceLabel)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()

            Picker("Period", selection: $state.dashboardFilter.timeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
        }
    }

    private var deviceLabel: String {
        if appState.dashboardFilter.selectedSources.isEmpty {
            return "All Devices"
        }
        if appState.dashboardFilter.selectedSources.count == 1,
           let source = appState.dashboardFilter.selectedSources.first {
            return source
        }
        return "\(appState.dashboardFilter.selectedSources.count) Devices"
    }

    private func isSingleSourceSelected(_ source: String) -> Bool {
        appState.dashboardFilter.selectedSources.count == 1
            && appState.dashboardFilter.selectedSources.contains(source)
    }

    private func selectSingleSource(_ source: String) {
        if isSingleSourceSelected(source) {
            appState.dashboardFilter.selectedSources = []
        } else {
            appState.dashboardFilter.selectedSources = [source]
        }
    }
}

// MARK: - Models

private struct ModelsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\ModelUsageEntry.totalCost, order: .reverse)]

    private var sortedModels: [ModelUsageEntry] {
        appState.modelBreakdown.sorted(using: sortOrder)
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading models…")
        } else if appState.modelBreakdown.isEmpty {
            ContentUnavailableView("No Models", systemImage: "cpu", description: Text("Model data will appear here once usage is recorded."))
        } else {
            VStack(spacing: 0) {
                UnifiedFilterBar()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Table(sortedModels, sortOrder: $sortOrder) {
                    TableColumn("Model", value: \.model) { entry in
                        Text(entry.model)
                            .fontWeight(.medium)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Input", value: \.inputTokens) { entry in
                        Text(CauditFormatter.tokens(entry.inputTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Output", value: \.outputTokens) { entry in
                        Text(CauditFormatter.tokens(entry.outputTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Cache", value: \.cacheTokens) { entry in
                        Text(CauditFormatter.tokens(entry.cacheTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Cost", value: \.totalCost) { entry in
                        Text(CauditFormatter.costDetail(entry.totalCost))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                    .width(ideal: 80)
                }
            }
        }
    }
}

// MARK: - Tools

private struct ToolsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\ToolUsageEntry.usageCount, order: .reverse)]

    private var sortedTools: [ToolUsageEntry] {
        appState.toolBreakdown.sorted(using: sortOrder)
    }

    private var totalCalls: Int {
        appState.toolBreakdown.reduce(0) { $0 + $1.usageCount }
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading tool data…")
        } else if appState.toolBreakdown.isEmpty {
            ContentUnavailableView("No Tool Data", systemImage: "wrench.and.screwdriver", description: Text("Tool usage data will appear here once recorded."))
        } else {
            VStack(spacing: 0) {
                UnifiedFilterBar()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Table(sortedTools, sortOrder: $sortOrder) {
                    TableColumn("Tool", value: \.name) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: toolIcon(entry.name))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(entry.name)
                                .fontWeight(.medium)
                        }
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Usage Count", value: \.usageCount) { entry in
                        Text("\(entry.usageCount)")
                            .monospacedDigit()
                    }
                    .width(ideal: 100)

                    TableColumn("Percentage") { entry in
                        let pct = totalCalls > 0 ? Double(entry.usageCount) / Double(totalCalls) * 100 : 0
                        HStack(spacing: 8) {
                            ProgressView(value: Double(entry.usageCount), total: Double(max(totalCalls, 1)))
                                .frame(width: 80)
                            Text(String(format: "%.1f%%", pct))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                    .width(ideal: 160)
                }
            }
        }
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "square.and.pencil"
        case "Edit": return "pencil.line"
        case "Bash": return "terminal"
        case "Glob": return "doc.text.magnifyingglass"
        case "Grep": return "magnifyingglass"
        case "Agent": return "person.2"
        case "WebSearch": return "globe"
        case "WebFetch": return "arrow.down.doc"
        default: return "wrench"
        }
    }
}

// MARK: - Components

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    var detail: String? = nil
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

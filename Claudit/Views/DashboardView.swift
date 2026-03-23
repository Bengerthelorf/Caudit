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

    // MARK: - Back/Forward History

    @State private var backStack: [(tab: DashboardTab?, session: SessionInfo?)] = []
    @State private var forwardStack: [(tab: DashboardTab?, session: SessionInfo?)] = []
    @State private var isNavigating = false

    private func pushHistory() {
        backStack.append((tab: appState.selectedTab, session: appState.selectedSessionForDetail))
        forwardStack.removeAll()
    }

    private func goBack() {
        guard let previous = backStack.popLast() else { return }
        isNavigating = true
        forwardStack.append((tab: appState.selectedTab, session: appState.selectedSessionForDetail))
        appState.selectedTab = previous.tab
        appState.selectedSessionForDetail = previous.session
    }

    private func goForward() {
        guard let next = forwardStack.popLast() else { return }
        isNavigating = true
        backStack.append((tab: appState.selectedTab, session: appState.selectedSessionForDetail))
        appState.selectedTab = next.tab
        appState.selectedSessionForDetail = next.session
    }

    private var tabBinding: Binding<DashboardTab?> {
        Binding(
            get: { appState.selectedTab },
            set: { newTab in
                guard newTab != appState.selectedTab else { return }
                pushHistory()
                appState.selectedTab = newTab
                appState.selectedSessionForDetail = nil
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(DashboardTab.allCases, selection: tabBinding) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Claudit")
            .frame(minWidth: 200, idealWidth: 300)
        } detail: {
            NavigationStack {
                Group {
                    if let session = appState.selectedSessionForDetail {
                        SessionDetailView(session: session)
                            .id(session.sessionId)
                            .navigationTitle(session.displayName)
                            .navigationSubtitle(
                                "\(session.project) · \(ClauditFormatter.duration(session.duration)) · \(ClauditFormatter.costDetail(session.totalCost)) · \(ClauditFormatter.tokensWithUnit(session.totalTokens))"
                            )
                    } else {
                        tabContent
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        ControlGroup {
                            Button(action: goBack) {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .disabled(backStack.isEmpty)

                            Button(action: goForward) {
                                Label("Forward", systemImage: "chevron.right")
                            }
                            .disabled(forwardStack.isEmpty)
                        }
                        .controlGroupStyle(.navigation)
                    }

                    if appState.selectedSessionForDetail != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                if let session = appState.selectedSessionForDetail {
                                    AppDelegate.shared.openSessionWindow(session: session)
                                }
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("Open in separate window")
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .onChange(of: appState.selectedSessionForDetail) { oldValue, newValue in
            if isNavigating {
                isNavigating = false
                return
            }
            guard oldValue != newValue, newValue != nil else { return }
            backStack.append((tab: appState.selectedTab, session: oldValue))
            forwardStack.removeAll()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
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

// MARK: - Source Colors

enum SourceColor {
    static let localColor: Color = Palette.blue
    private static let remotePalette: [Color] = [
        Palette.terracotta,
        Palette.sage,
        Palette.rose,
        Palette.adaptive(light: (0.68, 0.72, 0.80), dark: (0.74, 0.78, 0.86)),
        Palette.lavender,
        Palette.sand,
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

// MARK: - Palette

enum Palette {
    static let blue       = adaptive(light: (0.56, 0.65, 0.75), dark: (0.62, 0.72, 0.82))
    static let rose       = adaptive(light: (0.76, 0.58, 0.63), dark: (0.82, 0.64, 0.69))
    static let sage       = adaptive(light: (0.60, 0.72, 0.68), dark: (0.66, 0.78, 0.74))
    static let terracotta = adaptive(light: (0.78, 0.62, 0.56), dark: (0.84, 0.68, 0.62))
    static let lavender   = adaptive(light: (0.72, 0.66, 0.76), dark: (0.78, 0.72, 0.82))
    static let sand       = adaptive(light: (0.78, 0.74, 0.60), dark: (0.84, 0.80, 0.66))
    static let olive      = adaptive(light: (0.62, 0.66, 0.56), dark: (0.68, 0.72, 0.62))
    static let coral      = adaptive(light: (0.82, 0.62, 0.58), dark: (0.88, 0.68, 0.64))

    static let quotaGood   = adaptive(light: (0.60, 0.72, 0.64), dark: (0.50, 0.78, 0.56))
    static let quotaWarn   = adaptive(light: (0.80, 0.72, 0.52), dark: (0.88, 0.80, 0.50))
    static let quotaDanger = adaptive(light: (0.78, 0.54, 0.54), dark: (0.90, 0.50, 0.50))

    static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1.0)
        }))
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
                        UnifiedFilterBar(showTimeRange: false)
                    }

                    SectionHeader(title: "Usage Summary", icon: "dollarsign.circle")

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        StatCard(
                            label: "Today",
                            value: ClauditFormatter.costDetail(appState.todayUsage.totalCost),
                            detail: ClauditFormatter.tokensWithUnit(appState.todayUsage.totalTokens),
                            color: Palette.blue
                        )
                        StatCard(
                            label: "This Month",
                            value: ClauditFormatter.costDetail(appState.monthUsage.totalCost),
                            detail: ClauditFormatter.tokensWithUnit(appState.monthUsage.totalTokens),
                            color: Palette.lavender
                        )
                        StatCard(
                            label: "All Time",
                            value: ClauditFormatter.costDetail(appState.allTimeUsage.totalCost),
                            detail: ClauditFormatter.tokensWithUnit(appState.allTimeUsage.totalTokens),
                            color: Palette.sage
                        )
                        if let rate = appState.burnRate {
                            StatCard(
                                label: "Burn Rate",
                                value: ClauditFormatter.costDetail(rate),
                                detail: "per day · ~\(ClauditFormatter.cost(rate * 30))/mo",
                                color: Palette.terracotta
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
        if pct < 50 { return Palette.quotaGood }
        if pct < 80 { return Palette.quotaWarn }
        return Palette.quotaDanger
    }
}

// MARK: - Heatmap

private let heatmapGreens: [Color] = [
    Palette.adaptive(light: (0.92, 0.93, 0.90), dark: (0.22, 0.24, 0.22)),
    Palette.adaptive(light: (0.61, 0.91, 0.66), dark: (0.30, 0.60, 0.35)),
    Palette.adaptive(light: (0.25, 0.77, 0.33), dark: (0.25, 0.72, 0.33)),
    Palette.adaptive(light: (0.19, 0.56, 0.25), dark: (0.22, 0.62, 0.28)),
    Palette.adaptive(light: (0.13, 0.37, 0.17), dark: (0.18, 0.52, 0.24)),
]

private func heatmapColor(_ intensity: Double, hasData: Bool) -> Color {
    if !hasData { return heatmapGreens[0].opacity(0.3) }
    if intensity == 0 { return heatmapGreens[0].opacity(0.5) }
    if intensity < 0.25 { return heatmapGreens[1] }
    if intensity < 0.50 { return heatmapGreens[2] }
    if intensity < 0.75 { return heatmapGreens[3] }
    return heatmapGreens[4]
}

private struct HeatmapFooter: View {
    var hoveredInfo: String?

    var body: some View {
        HStack(spacing: 4) {
            if let info = hoveredInfo {
                Text(info)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            Text("Less").font(.caption2).foregroundStyle(.tertiary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level == 0 ? heatmapGreens[0].opacity(0.5) : heatmapGreens[level])
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.caption2).foregroundStyle(.tertiary)
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredInfo)
    }
}

// MARK: - Today Heatmap

private struct TodayHeatmap: View {
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

private struct WeekHeatmap: View {
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

private struct MonthHeatmap: View {
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

private struct CalendarCell {
    let date: Date
    let label: String
    let cost: Double
    let hasData: Bool
    var isFuture: Bool = false
}

private struct GitHubCalendarHeatmap: View {
    let dailyHistory: [DailyUsage]
    var minWeeks: Int = 75
    var cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 2
    @State private var hoveredInfo: String?

    var body: some View {
        let grid = buildGrid(minWeeks: minWeeks)
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

                            let step = cellSize + cellSpacing
                            HStack(spacing: cellSpacing) {
                                ForEach(grid.indices, id: \.self) { weekIdx in
                                    VStack(spacing: cellSpacing) {
                                        ForEach(0..<7, id: \.self) { dayIdx in
                                            cellRect(grid[weekIdx][dayIdx], maxCost: maxCost)
                                        }
                                    }
                                }
                            }
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    let week = Int(loc.x / step)
                                    let day = Int(loc.y / step)
                                    if week >= 0, week < grid.count, day >= 0, day < 7 {
                                        let cell = grid[week][day]
                                        if !cell.isFuture {
                                            hoveredInfo = cell.hasData
                                                ? "\(cell.label)  \(ClauditFormatter.costDetail(cell.cost))"
                                                : cell.label
                                        } else {
                                            hoveredInfo = nil
                                        }
                                    }
                                case .ended:
                                    hoveredInfo = nil
                                }
                            }
                        }
                        .padding(4)
                    }
                    .defaultScrollAnchor(.trailing)

                    HeatmapFooter(hoveredInfo: hoveredInfo)
                }
            }
        }
    }

    @ViewBuilder
    private func monthLabelsRow(grid: [[CalendarCell]]) -> some View {
        let labels = computeMonthLabels(grid: grid)

        HStack(spacing: cellSpacing) {
            ForEach(grid.indices, id: \.self) { weekIdx in
                if let label = labels[weekIdx] {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: cellSize, alignment: .leading)
                } else {
                    Color.clear.frame(width: cellSize, height: 10)
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

    private func cellRect(_ cell: CalendarCell, maxCost: Double) -> some View {
        let intensity = cell.isFuture ? 0 : (maxCost > 0 ? cell.cost / maxCost : 0)
        return RoundedRectangle(cornerRadius: 2)
            .fill(cell.isFuture ? Color.clear : heatmapColor(intensity, hasData: cell.hasData))
            .frame(width: cellSize, height: cellSize)
    }

    private func buildGrid(minWeeks: Int) -> [[CalendarCell]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM d, yyyy"

        var costByJulian: [Int: Double] = [:]
        for day in dailyHistory {
            if let jd = calendar.ordinality(of: .day, in: .era, for: day.date) {
                costByJulian[jd, default: 0] += day.totalCost
            }
        }

        let todayWeekday = calendar.component(.weekday, from: today)
        let endDate = calendar.date(byAdding: .day, value: 7 - todayWeekday, to: today)!

        let firstDate = dailyHistory.first?.date ?? today
        let dataStart: Date
        if minWeeks > 0 {
            let minStart = calendar.date(byAdding: .weekOfYear, value: -(minWeeks - 1), to: endDate)!
            dataStart = min(firstDate, minStart)
        } else {
            dataStart = dailyHistory.isEmpty ? today : firstDate
        }

        let startWeekday = calendar.component(.weekday, from: dataStart)
        let startDate = calendar.date(byAdding: .day, value: -(startWeekday - 1), to: dataStart)!

        var grid: [[CalendarCell]] = []
        var current = startDate

        while current <= endDate {
            var week: [CalendarCell] = []
            for _ in 0..<7 {
                let isFuture = current > today
                let jd = calendar.ordinality(of: .day, in: .era, for: current) ?? 0
                let cost = isFuture ? nil : costByJulian[jd]
                week.append(CalendarCell(
                    date: current,
                    label: labelFormatter.string(from: current),
                    cost: cost ?? 0,
                    hasData: cost != nil,
                    isFuture: isFuture
                ))
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }
            grid.append(week)
        }

        return grid
    }
}

// MARK: - Trend Chart

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
                    .foregroundStyle(Palette.blue.gradient)
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
                    Text(ClauditFormatter.cost(cost))
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

                    UnifiedFilterBar(showTimeRange: false)
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
                        Text(ClauditFormatter.duration(session.duration))
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
                        Text(ClauditFormatter.tokensWithUnit(session.totalTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 90)

                    TableColumn("Cost", value: \.totalCost) { session in
                        Text(ClauditFormatter.costDetail(session.totalCost))
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
                UnifiedFilterBar(showTimeRange: false)
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
                        Text(ClauditFormatter.tokensWithUnit(project.totalTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 90)

                    TableColumn("Cost", value: \.totalCost) { project in
                        Text(ClauditFormatter.costDetail(project.totalCost))
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
    var showTimeRange: Bool = true

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

            if showTimeRange {
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
                UnifiedFilterBar(showTimeRange: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Table(sortedModels, sortOrder: $sortOrder) {
                    TableColumn("Model", value: \.model) { entry in
                        Text(entry.model)
                            .fontWeight(.medium)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Input", value: \.inputTokens) { entry in
                        Text(ClauditFormatter.tokens(entry.inputTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Output", value: \.outputTokens) { entry in
                        Text(ClauditFormatter.tokens(entry.outputTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Cache", value: \.cacheTokens) { entry in
                        Text(ClauditFormatter.tokens(entry.cacheTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Cost", value: \.totalCost) { entry in
                        Text(ClauditFormatter.costDetail(entry.totalCost))
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
                UnifiedFilterBar(showTimeRange: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Table(sortedTools, sortOrder: $sortOrder) {
                    TableColumn("Tool", value: \.name) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: ClauditFormatter.toolIcon(entry.name))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

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
    @State private var selectedTab: DashboardTab? = .overview

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
            .navigationTitle("Caudit")
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch selectedTab {
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

    private var chartEntries: [ChartEntry] {
        let sources = appState.availableSources
        return appState.dailyHistory.flatMap { day in
            // Sort: Local first (bottom of stack), then remotes in consistent order
            sources.compactMap { source in
                guard let cost = day.costBySource[source], cost > 0 else { return nil }
                return ChartEntry(dateString: day.dateString, source: source, cost: cost)
            }
        }
    }

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

                    GroupBox {
                        if appState.dailyHistory.isEmpty || chartEntries.isEmpty {
                            Text("No data yet")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else if hasSources {
                            // Stacked bars by source
                            Chart(chartEntries) { entry in
                                BarMark(
                                    x: .value("Date", entry.dateString),
                                    y: .value("Cost", entry.cost)
                                )
                                .foregroundStyle(by: .value("Source", entry.source))
                                .cornerRadius(4)
                            }
                            .chartForegroundStyleScale(
                                domain: appState.availableSources,
                                range: appState.availableSources.map {
                                    SourceColor.color(for: $0, allSources: appState.availableSources)
                                }
                            )
                            .chartYAxis {
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
                            .chartLegend(position: .bottom, spacing: 8)
                            .frame(height: 220)
                            .padding(.top, 4)
                        } else {
                            // Simple bars when single source
                            Chart(appState.dailyHistory) { day in
                                BarMark(
                                    x: .value("Date", day.dateString),
                                    y: .value("Cost", day.totalCost)
                                )
                                .foregroundStyle(.blue.gradient)
                                .cornerRadius(4)
                            }
                            .chartYAxis {
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
                            .frame(height: 200)
                            .padding(.top, 4)
                        }
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

private struct ChartEntry: Identifiable {
    var id: String { "\(dateString)-\(source)" }
    let dateString: String
    let source: String
    let cost: Double
}

// MARK: - Activity

private struct ActivityPage: View {
    @Environment(AppState.self) private var appState

    private let displayDayOrder = [1, 2, 3, 4, 5, 6, 0]  // Mon-Sun
    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let dayFullLabels = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var maxCount: Int {
        appState.heatmapData.map(\.messageCount).max() ?? 0
    }

    private var totalCalls: Int {
        appState.heatmapData.reduce(0) { $0 + $1.messageCount }
    }

    private var peakEntry: HeatmapEntry? {
        appState.heatmapData.max(by: { $0.messageCount < $1.messageCount })
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
                    if appState.availableSources.count > 1 {
                        FilterBar()
                    }

                    SectionHeader(title: "Activity Patterns", icon: "chart.dots.scatter")

                    GroupBox {
                        if totalCalls == 0 {
                            Text("No activity data yet")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                // Hour labels
                                HStack(spacing: 2) {
                                    Text("")
                                        .frame(width: 32)
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
                                        .frame(width: 18, alignment: .center)
                                    }
                                }

                                // Day rows
                                ForEach(0..<7, id: \.self) { displayIndex in
                                    let day = displayDayOrder[displayIndex]
                                    HStack(spacing: 2) {
                                        Text(dayLabels[displayIndex])
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32, alignment: .trailing)

                                        ForEach(0..<24, id: \.self) { hour in
                                            let entry = appState.heatmapData[day * 24 + hour]
                                            heatmapCell(entry)
                                        }
                                    }
                                }

                                // Legend
                                HStack(spacing: 4) {
                                    Spacer()
                                    Text("Less")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    ForEach(0..<5, id: \.self) { level in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(legendColor(level: level))
                                            .frame(width: 12, height: 12)
                                    }
                                    Text("More")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.top, 8)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    SectionHeader(title: "Summary", icon: "chart.bar.xaxis")

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        StatCard(
                            label: "Total Calls",
                            value: CauditFormatter.tokens(totalCalls),
                            color: .blue
                        )
                        if let peak = peakEntry, peak.messageCount > 0 {
                            StatCard(
                                label: "Peak Day",
                                value: dayFullLabels[peak.dayOfWeek],
                                color: .purple
                            )
                            StatCard(
                                label: "Peak Hour",
                                value: String(format: "%d:00", peak.hour),
                                color: .orange
                            )
                            StatCard(
                                label: "Peak Slot Cost",
                                value: CauditFormatter.costDetail(peak.totalCost),
                                detail: "\(peak.messageCount) calls",
                                color: .green
                            )
                        }
                    }

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
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private func heatmapCell(_ entry: HeatmapEntry) -> some View {
        let intensity = maxCount > 0 ? Double(entry.messageCount) / Double(maxCount) : 0
        RoundedRectangle(cornerRadius: 2)
            .fill(cellColor(intensity))
            .frame(width: 18, height: 18)
            .help("\(dayFullLabels[entry.dayOfWeek]) \(entry.hour):00 – \(entry.messageCount) calls, \(CauditFormatter.costDetail(entry.totalCost))")
    }

    private func cellColor(_ intensity: Double) -> Color {
        if intensity == 0 { return Color.primary.opacity(0.05) }
        return Color.accentColor.opacity(0.15 + intensity * 0.75)
    }

    private func legendColor(level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.05)
        case 1: return Color.accentColor.opacity(0.25)
        case 2: return Color.accentColor.opacity(0.45)
        case 3: return Color.accentColor.opacity(0.65)
        case 4: return Color.accentColor.opacity(0.90)
        default: return .clear
        }
    }
}

// MARK: - Sessions

private struct SessionsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\SessionInfo.lastTimestamp, order: .reverse)]

    private var sortedSessions: [SessionInfo] {
        appState.sessionBreakdown.sorted(using: sortOrder)
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading sessions…")
        } else if appState.sessionBreakdown.isEmpty {
            ContentUnavailableView("No Sessions", systemImage: "bubble.left.and.bubble.right", description: Text("Session data will appear here once usage is recorded."))
        } else {
            VStack(spacing: 0) {
                FilterBar(showTimeRange: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Table(sortedSessions, sortOrder: $sortOrder) {
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
            }
        }
    }
}

// MARK: - Projects

private struct ProjectsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\ProjectUsage.totalCost, order: .reverse)]

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

                Table(sortedProjects, sortOrder: $sortOrder) {
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
            }
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
                FilterBar(showTimeRange: true)
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
                FilterBar(showTimeRange: true)
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

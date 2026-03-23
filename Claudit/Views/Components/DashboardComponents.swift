import SwiftUI
import Charts

// MARK: - Loading Placeholder

struct LoadingPlaceholder: View {
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

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

// MARK: - Stat Card

struct StatCard: View {
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

// MARK: - Trend Chart

enum ChartGranularity {
    case daily
    case hourly
}

struct DateChartEntry: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(source)" }
    let date: Date
    let source: String
    let cost: Double
}

struct TrendChart: View {
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

// MARK: - Unified Filter Bar (Menu-based)

struct UnifiedFilterBar: View {
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

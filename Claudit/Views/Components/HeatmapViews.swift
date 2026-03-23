import SwiftUI

// MARK: - Heatmap

let heatmapGreens: [Color] = [
    Palette.adaptive(light: (0.92, 0.93, 0.90), dark: (0.22, 0.24, 0.22)),
    Palette.adaptive(light: (0.61, 0.91, 0.66), dark: (0.30, 0.60, 0.35)),
    Palette.adaptive(light: (0.25, 0.77, 0.33), dark: (0.25, 0.72, 0.33)),
    Palette.adaptive(light: (0.19, 0.56, 0.25), dark: (0.22, 0.62, 0.28)),
    Palette.adaptive(light: (0.13, 0.37, 0.17), dark: (0.18, 0.52, 0.24)),
]

func heatmapColor(_ intensity: Double, hasData: Bool) -> Color {
    if !hasData { return heatmapGreens[0].opacity(0.3) }
    if intensity == 0 { return heatmapGreens[0].opacity(0.5) }
    if intensity < 0.25 { return heatmapGreens[1] }
    if intensity < 0.50 { return heatmapGreens[2] }
    if intensity < 0.75 { return heatmapGreens[3] }
    return heatmapGreens[4]
}

// MARK: - Heatmap Footer

struct HeatmapFooter: View {
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

// MARK: - Calendar Cell

struct CalendarCell {
    let date: Date
    let label: String
    let cost: Double
    let hasData: Bool
    var isFuture: Bool = false
}

// MARK: - GitHub Calendar Heatmap

struct GitHubCalendarHeatmap: View {
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

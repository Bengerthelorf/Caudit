import SwiftUI
import Charts

enum HistoryTimeScale: String, CaseIterable {
    case fiveHours = "5h"
    case twentyFourHours = "24h"
    case sevenDays = "7d"
    case thirtyDays = "30d"

    var timeInterval: TimeInterval {
        switch self {
        case .fiveHours:        return 5 * 3600
        case .twentyFourHours:  return 24 * 3600
        case .sevenDays:        return 7 * 24 * 3600
        case .thirtyDays:       return 30 * 24 * 3600
        }
    }

    var stepInterval: TimeInterval {
        timeInterval / 2
    }
}

struct UsageHistoryChartView: View {
    @Environment(AppState.self) private var appState
    @State private var timeScale: HistoryTimeScale = .twentyFourHours
    @State private var windowEnd: Date = Date()

    private var windowStart: Date {
        windowEnd.addingTimeInterval(-timeScale.timeInterval)
    }

    private var sessionData: [UsageSnapshot] {
        appState.usageHistoryService.snapshots(type: .session, from: windowStart, to: windowEnd)
    }

    private var weeklyData: [UsageSnapshot] {
        appState.usageHistoryService.snapshots(type: .weekly, from: windowStart, to: windowEnd)
    }

    /// Projection: line from current usage to projected usage, clamped to chart bounds.
    private var sessionProjection: (start: (Date, Double), end: (Date, Double))? {
        guard let quota = appState.quotaInfo,
              let resetAt = quota.fiveHourResetAt,
              resetAt > Date() else { return nil }

        let now = Date()
        let currentPct = quota.fiveHourUtilization
        let elapsed = PaceService.fiveHourElapsedFraction(resetAt: resetAt)
        guard elapsed >= PaceService.minimumElapsedFraction, currentPct > 0 else { return nil }

        let projected = currentPct / elapsed

        // Clamp end date to chart window to prevent line from extending beyond visible area
        let endDate = min(resetAt, windowEnd)
        // Interpolate projected value at clamped end date
        let totalDuration = resetAt.timeIntervalSince(now)
        let clampedDuration = endDate.timeIntervalSince(now)
        let fraction = totalDuration > 0 ? clampedDuration / totalDuration : 1
        let endPct = currentPct + (projected - currentPct) * fraction

        return (start: (now, currentPct), end: (endDate, endPct))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Time Scale", selection: $timeScale) {
                    ForEach(HistoryTimeScale.allCases, id: \.self) { scale in
                        Text(scale.rawValue).tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: timeScale) { _, _ in
                    windowEnd = Date()
                }

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        windowEnd = windowEnd.addingTimeInterval(-timeScale.stepInterval)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Button("Now") {
                        windowEnd = Date()
                    }
                    .buttonStyle(.borderless)
                    .disabled(abs(windowEnd.timeIntervalSinceNow) < 60)

                    Button {
                        let newEnd = windowEnd.addingTimeInterval(timeScale.stepInterval)
                        windowEnd = min(newEnd, Date())
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(abs(windowEnd.timeIntervalSinceNow) < 60)
                }
            }

            if sessionData.isEmpty && weeklyData.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "chart.line.downtrend.xyaxis",
                    description: Text("Usage history will appear as quota data is recorded over time.")
                )
                .frame(height: 160)
            } else {
                Chart {
                    ForEach(sessionData) { snapshot in
                        LineMark(
                            x: .value("Time", snapshot.timestamp),
                            y: .value("Usage", snapshot.percentage)
                        )
                        .foregroundStyle(by: .value("Type", "5h Session"))
                        .interpolationMethod(.stepEnd)
                    }
                    ForEach(weeklyData) { snapshot in
                        LineMark(
                            x: .value("Time", snapshot.timestamp),
                            y: .value("Usage", snapshot.percentage)
                        )
                        .foregroundStyle(by: .value("Type", "7d Weekly"))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(dash: [4, 3]))
                    }

                    // Projection line from latest session point to reset time
                    if let projection = sessionProjection {
                        LineMark(
                            x: .value("Time", projection.start.0),
                            y: .value("Usage", projection.start.1)
                        )
                        .foregroundStyle(by: .value("Type", "Projected"))
                        .lineStyle(StrokeStyle(dash: [6, 4]))

                        LineMark(
                            x: .value("Time", projection.end.0),
                            y: .value("Usage", projection.end.1)
                        )
                        .foregroundStyle(by: .value("Type", "Projected"))
                        .lineStyle(StrokeStyle(dash: [6, 4]))
                    }

                    // 100% threshold line
                    RuleMark(y: .value("Limit", 100))
                        .foregroundStyle(.red.opacity(0.3))
                        .lineStyle(StrokeStyle(dash: [4, 4]))
                }
                .chartXScale(domain: windowStart...windowEnd)
                .chartYScale(domain: 0...max(100, (sessionData + weeklyData).map(\.percentage).max() ?? 100))
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%")
                            }
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "5h Session": Color.blue,
                    "7d Weekly": Color.orange,
                    "Projected": Color.red.opacity(0.6),
                ])
                .chartLegend(position: .bottom)
                .frame(height: 160)
            }
        }
        .onAppear { windowEnd = Date() }
    }
}

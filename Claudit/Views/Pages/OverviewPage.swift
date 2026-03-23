import SwiftUI

// MARK: - Overview

struct OverviewPage: View {
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

                    if appState.quotaInfo != nil {
                        SectionHeader(title: "Usage History", icon: "chart.line.uptrend.xyaxis")
                        UsageHistoryChartView()
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

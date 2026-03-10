import SwiftUI

struct UsageView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if !appState.hasLoadedUsage {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading usage data...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CauditFormatter.costDetail(appState.todayUsage.totalCost))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                VStack(spacing: 6) {
                    TokenRow(label: "Input", tokens: appState.todayUsage.inputTokens, color: .blue)
                    TokenRow(label: "Output", tokens: appState.todayUsage.outputTokens, color: .green)
                    TokenRow(label: "Cache Read", tokens: appState.todayUsage.cacheReadTokens, color: .cyan)
                    TokenRow(label: "Cache Write", tokens: appState.todayUsage.cacheCreationTokens, color: .orange)
                }

                Divider()

                HStack(spacing: 0) {
                    PeriodSummary(title: "This Month", cost: appState.monthUsage.totalCost, tokens: appState.monthUsage.totalTokens)
                    Spacer()
                    PeriodSummary(title: "All Time", cost: appState.allTimeUsage.totalCost, tokens: appState.allTimeUsage.totalTokens)
                    Spacer()
                }

                if !appState.modelBreakdown.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("By Model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(appState.modelBreakdown) { entry in
                            HStack {
                                Text(entry.model)
                                    .font(.system(size: 11))
                                Spacer()
                                Text(CauditFormatter.tokens(entry.totalTokens))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Text(CauditFormatter.costDetail(entry.totalCost))
                                    .font(.system(size: 11, weight: .medium))
                                    .monospacedDigit()
                                    .frame(minWidth: 55, alignment: .trailing)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

}

struct TokenRow: View {
    let label: String
    let tokens: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(CauditFormatter.tokens(tokens))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }
}

struct PeriodSummary: View {
    let title: String
    let cost: Double
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(CauditFormatter.costDetail(cost))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(CauditFormatter.tokensWithUnit(tokens))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

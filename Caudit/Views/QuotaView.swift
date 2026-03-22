import SwiftUI

struct QuotaView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 14) {
                if let quota = appState.quotaInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("5h Window")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let remaining = quota.fiveHourTimeRemaining {
                                Label(CauditFormatter.duration(remaining), systemImage: "clock")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("\(Int(quota.fiveHourUtilization))%")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(quotaColor(quota.fiveHourUtilization))
                            .accessibilityLabel("5-hour quota: \(Int(quota.fiveHourUtilization)) percent")
                        QuotaBar(percentage: quota.fiveHourUtilization)
                    }

                    Divider()

                    QuotaRow(
                        title: "7-Day",
                        percentage: quota.sevenDayUtilization,
                        remaining: quota.sevenDayTimeRemaining
                    )

                    if let opus = quota.sevenDayOpusUtilization {
                        QuotaRow(title: "Opus (7d)", percentage: opus)
                    }
                    if let sonnet = quota.sevenDaySonnetUtilization {
                        QuotaRow(title: "Sonnet (7d)", percentage: sonnet)
                    }

                    Text("Updated \(quota.lastUpdated.formatted(.dateTime.hour().minute()))")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                        .padding(.top, 8)

                } else if appState.isLoadingQuota {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)

                } else if let error = appState.quotaError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            appState.refreshQuota()
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)

                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Run 'claude auth login' to connect.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func quotaColor(_ pct: Double) -> Color {
        if pct < 50 { return .primary }
        if pct < 80 { return Palette.quotaWarn }
        return Palette.quotaDanger
    }
}

struct QuotaRow: View {
    let title: String
    let percentage: Double
    var remaining: TimeInterval? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let remaining {
                    Label(CauditFormatter.duration(remaining), systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            QuotaBar(percentage: percentage, height: 5)
        }
    }
}

struct QuotaBar: View {
    let percentage: Double
    var height: CGFloat = 6

    private var color: Color {
        if percentage < 50 { return Palette.quotaGood }
        if percentage < 80 { return Palette.quotaWarn }
        return Palette.quotaDanger
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color.gradient)
                    .frame(width: geo.size.width * min(max(percentage / 100, 0), 1.0))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Quota usage")
        .accessibilityValue("\(Int(percentage)) percent")
    }
}

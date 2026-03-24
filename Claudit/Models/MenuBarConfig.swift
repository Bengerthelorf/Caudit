import Foundation

/// Configurable menu bar display components.
struct MenuBarConfig: Codable, Equatable {
    var showCost: Bool = true
    var showQuotaPercent: Bool = false
    var showPace: Bool = false
    var showResetTime: Bool = false
    var showWeeklyPercent: Bool = false

    /// Generate the display text for the menu bar status item.
    func formatText(
        todayCost: Double?,
        quotaPercent: Double?,
        pace: String?,
        resetTimeRemaining: TimeInterval?,
        weeklyPercent: Double?
    ) -> String {
        var parts: [String] = []

        if showCost, let cost = todayCost {
            parts.append(formatCost(cost))
        }

        if showQuotaPercent, let pct = quotaPercent {
            parts.append("\(Int(pct))%")
        }

        if showPace, let pace {
            parts.append(pace)
        }

        if showResetTime, let remaining = resetTimeRemaining, remaining > 0 {
            parts.append("⏱\(formatDuration(remaining))")
        }

        if showWeeklyPercent, let pct = weeklyPercent {
            parts.append("7d:\(Int(pct))%")
        }

        return parts.isEmpty ? "--" : parts.joined(separator: " ")
    }

    private func formatCost(_ value: Double) -> String {
        if value < 0.01 { return "$0.00" }
        if value < 10 { return String(format: "$%.2f", value) }
        return String(format: "$%.0f", value)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }
}

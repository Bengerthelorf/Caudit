import Foundation

struct PaceService {
    /// Minimum elapsed fraction (3%) before pace calculation is meaningful.
    static let minimumElapsedFraction: Double = 0.03

    /// Calculate the pace status for a quota window.
    ///
    /// - Parameters:
    ///   - usedPercentage: Current usage percentage (0-100+).
    ///   - elapsedFraction: Fraction of the window that has elapsed (0.0-1.0).
    /// - Returns: The pace status, or nil if not enough time has elapsed.
    static func calculatePace(usedPercentage: Double, elapsedFraction: Double) -> PaceStatus? {
        guard elapsedFraction >= minimumElapsedFraction else { return nil }

        let projectedUsage = usedPercentage / elapsedFraction
        return classify(projectedUsage)
    }

    /// Calculate elapsed fraction for a 5-hour window given the reset time.
    static func fiveHourElapsedFraction(resetAt: Date?) -> Double {
        guard let resetAt else { return 0 }
        let windowDuration: TimeInterval = 5 * 3600
        let remaining = resetAt.timeIntervalSinceNow
        guard remaining > 0 && remaining <= windowDuration else { return 0 }
        return (windowDuration - remaining) / windowDuration
    }

    /// Calculate elapsed fraction for a 7-day window given the reset time.
    static func sevenDayElapsedFraction(resetAt: Date?) -> Double {
        guard let resetAt else { return 0 }
        let windowDuration: TimeInterval = 7 * 24 * 3600
        let remaining = resetAt.timeIntervalSinceNow
        guard remaining > 0 && remaining <= windowDuration else { return 0 }
        return (windowDuration - remaining) / windowDuration
    }

    /// Classify a projected usage percentage into a pace tier.
    static func classify(_ projectedUsage: Double) -> PaceStatus {
        switch projectedUsage {
        case ..<50:    return .comfortable
        case ..<75:    return .onTrack
        case ..<90:    return .warming
        case ..<100:   return .pressing
        case ..<120:   return .critical
        default:       return .runaway
        }
    }
}

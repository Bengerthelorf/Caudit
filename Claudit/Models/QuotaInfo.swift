import Foundation

struct QuotaInfo: Sendable {
    let fiveHourUtilization: Double
    let fiveHourResetAt: Date?
    let sevenDayUtilization: Double
    let sevenDayResetAt: Date?
    let sevenDayOpusUtilization: Double?
    let sevenDaySonnetUtilization: Double?
    let lastUpdated: Date

    var fiveHourTimeRemaining: TimeInterval? {
        guard let resetAt = fiveHourResetAt else { return nil }
        let remaining = resetAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    var sevenDayTimeRemaining: TimeInterval? {
        guard let resetAt = sevenDayResetAt else { return nil }
        let remaining = resetAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }
}

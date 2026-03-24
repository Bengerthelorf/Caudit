import Foundation

/// Billing data from console.anthropic.com API.
struct ConsoleBilling: Sendable, Equatable {
    /// Current spend for the billing period.
    let currentSpend: Double
    /// Hard limit (maximum spend allowed).
    let hardLimit: Double?
    /// Soft limit (alert threshold).
    let softLimit: Double?

    /// Prepaid credit balance.
    let prepaidCredits: Double

    /// Per-API-key usage breakdown for the current period.
    let apiKeyUsage: [APIKeyUsage]

    /// When this data was last fetched.
    let lastUpdated: Date

    var spendPercentage: Double? {
        guard let limit = hardLimit, limit > 0 else { return nil }
        return currentSpend / limit * 100
    }

    var remainingBudget: Double? {
        guard let limit = hardLimit else { return nil }
        return max(limit - currentSpend, 0)
    }

    struct APIKeyUsage: Sendable, Equatable, Identifiable {
        var id: String { apiKeyId }
        let apiKeyId: String
        let apiKeyName: String?
        let cost: Double
    }
}

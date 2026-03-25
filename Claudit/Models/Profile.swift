import Foundation

/// Represents a Claude Code account profile.
/// Each profile corresponds to a separate set of OAuth credentials
/// backed up in the Keychain, enabling multi-account switching.
struct Profile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var isActive: Bool
    var autoSwitchOnLimit: Bool

    /// Quota source preference for this profile.
    var quotaSource: String

    /// When this profile was created.
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = false,
        autoSwitchOnLimit: Bool = false,
        quotaSource: String = QuotaSource.rateLimitHeaders.rawValue,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.autoSwitchOnLimit = autoSwitchOnLimit
        self.quotaSource = quotaSource
        self.createdAt = createdAt
    }
}

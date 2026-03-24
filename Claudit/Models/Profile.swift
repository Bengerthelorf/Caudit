import Foundation

/// Represents a user profile with its own credentials and settings.
struct Profile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var isActive: Bool
    var autoSwitchOnLimit: Bool

    /// Quota source preference for this profile.
    var quotaSource: String

    /// Path to Claude config dir (defaults to ~/.claude).
    var claudeConfigDir: String?

    /// Organization ID for Claude.ai session cookie quota.
    var claudeOrgId: String?

    /// Organization ID for console.anthropic.com billing.
    var consoleOrgId: String?

    /// When this profile was created.
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = false,
        autoSwitchOnLimit: Bool = false,
        quotaSource: String = QuotaSource.rateLimitHeaders.rawValue,
        claudeConfigDir: String? = nil,
        claudeOrgId: String? = nil,
        consoleOrgId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.autoSwitchOnLimit = autoSwitchOnLimit
        self.quotaSource = quotaSource
        self.claudeConfigDir = claudeConfigDir
        self.claudeOrgId = claudeOrgId
        self.consoleOrgId = consoleOrgId
        self.createdAt = createdAt
    }
}

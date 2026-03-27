import Foundation
import Security
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "ProfileManager")

/// Manages multiple Claude Code accounts with real credential switching.
///
/// On switch, backs up the current account's OAuth token from the system Keychain
/// and ~/.claude.json oauthAccount, then restores the target account's credentials.
/// Follows the same approach as CCSwitcher (XueshiQiao/CCSwitcher).
@MainActor @Observable
final class ProfileManager {
    private(set) var profiles: [Profile] = []
    private(set) var activeProfileId: UUID?

    private let storageURL: URL
    private static let backupKeychainService = "cc.ffitch.Claudit.profile.backups"
    private static let claudeKeychainService = "Claude Code-credentials"

    var activeProfile: Profile? {
        guard let id = activeProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    var hasMultipleProfiles: Bool {
        profiles.count > 1
    }

    init(storageURL: URL? = nil) {
        if let url = storageURL {
            self.storageURL = url
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("Claudit", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storageURL = dir.appendingPathComponent("profiles.json")
        }
        loadProfiles()
    }

    // MARK: - CRUD

    func addProfile(name: String) -> Profile {
        let profile = Profile(name: name)
        profiles.append(profile)
        if profiles.count == 1 {
            activeProfileId = profile.id
            var p = profile
            p.isActive = true
            profiles[profiles.count - 1] = p
        }
        saveProfiles()
        return profile
    }

    func updateProfile(_ profile: Profile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        saveProfiles()
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        deleteBackup(for: id)

        if activeProfileId == id {
            if let first = profiles.first {
                activeProfileId = first.id
                if let idx = profiles.firstIndex(where: { $0.id == first.id }) {
                    profiles[idx].isActive = true
                }
            }
        }
        saveProfiles()
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = name
        saveProfiles()
    }

    // MARK: - Account Switching

    /// Switch to a different profile by swapping Claude Code's live credentials.
    ///
    /// Flow (following CCSwitcher's approach):
    /// 1. Back up current account's credentials from Keychain + ~/.claude.json
    /// 2. Restore target account's credentials into Keychain + ~/.claude.json
    /// 3. Update active profile state
    func switchTo(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }), id != activeProfileId else { return }

        // Step 1: Back up current account
        if let currentId = activeProfileId {
            backupCurrentCredentials(profileId: currentId)
        }

        // Step 2: Restore target account
        restoreCredentials(profileId: id)

        // Step 3: Update state
        for i in profiles.indices {
            profiles[i].isActive = (profiles[i].id == id)
        }
        activeProfileId = id
        saveProfiles()
        logger.info("Switched to profile: \(id.uuidString)")
    }

    /// Auto-switch to the next profile with autoSwitchOnLimit enabled.
    @discardableResult
    func autoSwitchToNext() -> Profile? {
        guard let currentId = activeProfileId else { return nil }
        let candidates = profiles.filter { $0.id != currentId && $0.autoSwitchOnLimit }
        guard let next = candidates.first else { return nil }
        switchTo(next.id)
        return next
    }

    // MARK: - Credential Backup/Restore

    /// Read current Claude Code credentials from system Keychain and ~/.claude.json,
    /// then store them as a backup for the given profile.
    private func backupCurrentCredentials(profileId: UUID) {
        var backup: [String: String] = [:]

        // Read OAuth token from Keychain
        if let token = readClaudeKeychainToken() {
            backup["token"] = token
        }

        // Read oauthAccount from ~/.claude.json
        if let account = readClaudeJsonOAuthAccount() {
            backup["oauthAccount"] = account
        }

        guard !backup.isEmpty else { return }
        saveBackup(backup, for: profileId)
    }

    /// Restore a profile's backed-up credentials into Claude Code's live Keychain + ~/.claude.json.
    private func restoreCredentials(profileId: UUID) {
        guard let backup = loadBackup(for: profileId) else {
            logger.warning("No backup found for profile \(profileId.uuidString)")
            return
        }

        // Write OAuth token to Keychain
        if let token = backup["token"] {
            writeClaudeKeychainToken(token)
        }

        // Write oauthAccount to ~/.claude.json
        if let account = backup["oauthAccount"] {
            writeClaudeJsonOAuthAccount(account)
        }
    }

    // MARK: - Claude Code Keychain Access (via /usr/bin/security CLI)

    /// Read the live OAuth token from Claude Code's Keychain entry.
    private nonisolated func readClaudeKeychainToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", Self.claudeKeychainService,
            "-a", NSUserName(),
            "-w"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Write an OAuth token to Claude Code's Keychain entry (delete + add).
    private nonisolated func writeClaudeKeychainToken(_ token: String) {
        // Delete existing
        let delProcess = Process()
        delProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        delProcess.arguments = [
            "delete-generic-password",
            "-s", Self.claudeKeychainService,
            "-a", NSUserName()
        ]
        delProcess.standardOutput = Pipe()
        delProcess.standardError = Pipe()
        try? delProcess.run()
        delProcess.waitUntilExit()

        // Add new
        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        addProcess.arguments = [
            "add-generic-password",
            "-s", Self.claudeKeychainService,
            "-a", NSUserName(),
            "-w", token,
            "-U" // update if exists
        ]
        addProcess.standardOutput = Pipe()
        addProcess.standardError = Pipe()
        try? addProcess.run()
        addProcess.waitUntilExit()
    }

    // MARK: - ~/.claude.json Access

    private nonisolated static var claudeJsonPathStatic: String {
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? (NSHomeDirectory() + "/.claude")
        return configDir + ".json"  // ~/.claude.json (not ~/.claude/.json)
    }

    /// Read the oauthAccount block from ~/.claude.json as a JSON string.
    private nonisolated func readClaudeJsonOAuthAccount() -> String? {
        let path = Self.claudeJsonPathStatic
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthAccount = json["oauthAccount"] else { return nil }

        guard let accountData = try? JSONSerialization.data(withJSONObject: oauthAccount),
              let accountStr = String(data: accountData, encoding: .utf8) else { return nil }
        return accountStr
    }

    /// Write an oauthAccount block to ~/.claude.json, preserving other fields.
    private nonisolated func writeClaudeJsonOAuthAccount(_ accountJson: String) {
        let path = Self.claudeJsonPathStatic

        // Read existing
        var json: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        // Parse account JSON and merge
        guard let accountData = accountJson.data(using: .utf8),
              let account = try? JSONSerialization.jsonObject(with: accountData) else { return }

        json["oauthAccount"] = account

        // Write back
        guard let outputData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? outputData.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    // MARK: - Backup Storage (Keychain)

    private func saveBackup(_ backup: [String: String], for profileId: UUID) {
        // Load all backups, update this profile's, save back
        var allBackups = loadAllBackups()
        allBackups[profileId.uuidString] = backup
        guard let data = try? JSONSerialization.data(withJSONObject: allBackups) else { return }

        deleteAllBackupsFromKeychain()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.backupKeychainService,
            kSecAttrAccount as String: "all-accounts",
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadBackup(for profileId: UUID) -> [String: String]? {
        let allBackups = loadAllBackups()
        return allBackups[profileId.uuidString] as? [String: String]
    }

    private func deleteBackup(for profileId: UUID) {
        var allBackups = loadAllBackups()
        allBackups.removeValue(forKey: profileId.uuidString)
        guard let data = try? JSONSerialization.data(withJSONObject: allBackups) else { return }

        deleteAllBackupsFromKeychain()

        if !allBackups.isEmpty {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.backupKeychainService,
                kSecAttrAccount as String: "all-accounts",
                kSecValueData as String: data
            ]
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private func loadAllBackups() -> [String: Any] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.backupKeychainService,
            kSecAttrAccount as String: "all-accounts",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func deleteAllBackupsFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.backupKeychainService,
            kSecAttrAccount as String: "all-accounts"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Profile Persistence

    private func loadProfiles() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Profile].self, from: data),
              !decoded.isEmpty else {
            let defaultProfile = Profile(name: "Default", isActive: true)
            profiles = [defaultProfile]
            activeProfileId = defaultProfile.id
            saveProfiles()
            return
        }

        profiles = decoded
        activeProfileId = decoded.first(where: { $0.isActive })?.id ?? decoded.first?.id
    }

    func saveProfiles() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            logger.error("Failed to save profiles: \(error.localizedDescription)")
        }
    }
}

// MARK: - Credential Keys

enum ProfileCredentialKey: String, CaseIterable {
    case claudeSessionKey = "claudeSessionKey"
    case consoleSessionKey = "consoleSessionKey"
}

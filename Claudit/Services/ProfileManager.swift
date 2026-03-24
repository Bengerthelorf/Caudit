import Foundation
import Security
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "ProfileManager")

/// Manages multiple user profiles with per-profile credentials stored in Keychain.
@MainActor @Observable
final class ProfileManager {
    private(set) var profiles: [Profile] = []
    private(set) var activeProfileId: UUID?

    private let storageURL: URL
    private static let keychainServicePrefix = "cc.ffitch.Claudit.profile."

    var activeProfile: Profile? {
        guard let id = activeProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    var hasMultipleProfiles: Bool {
        profiles.count > 1
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Claudit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("profiles.json")

        loadProfiles()
    }

    // MARK: - CRUD

    func addProfile(name: String) -> Profile {
        let profile = Profile(name: name)
        profiles.append(profile)
        if profiles.count == 1 {
            switchTo(profile.id)
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
        guard profiles.count > 1 else { return } // Cannot delete last profile
        profiles.removeAll { $0.id == id }
        deleteCredentials(for: id)

        if activeProfileId == id {
            if let first = profiles.first {
                switchTo(first.id)
            }
        }
        saveProfiles()
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = name
        saveProfiles()
    }

    // MARK: - Switching

    func switchTo(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }

        // Deactivate all, activate target
        for i in profiles.indices {
            profiles[i].isActive = (profiles[i].id == id)
        }
        activeProfileId = id
        saveProfiles()
        logger.info("Switched to profile: \(id.uuidString)")
    }

    /// Auto-switch to the next profile with autoSwitchOnLimit enabled.
    /// Returns the profile switched to, or nil if no eligible profile found.
    @discardableResult
    func autoSwitchToNext() -> Profile? {
        guard let currentId = activeProfileId else { return nil }

        let candidates = profiles.filter { $0.id != currentId && $0.autoSwitchOnLimit }
        guard let next = candidates.first else { return nil }

        switchTo(next.id)
        return next
    }

    // MARK: - Per-Profile Credentials (Keychain)

    /// Store a credential for a profile.
    func saveCredential(profileId: UUID, key: ProfileCredentialKey, value: String) {
        let service = Self.keychainServicePrefix + profileId.uuidString
        let account = key.rawValue

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.warning("Failed to save credential \(key.rawValue) for profile \(profileId.uuidString): \(status)")
        }
    }

    /// Retrieve a credential for a profile.
    func loadCredential(profileId: UUID, key: ProfileCredentialKey) -> String? {
        let service = Self.keychainServicePrefix + profileId.uuidString
        let account = key.rawValue

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    /// Delete all credentials for a profile.
    private func deleteCredentials(for profileId: UUID) {
        let service = Self.keychainServicePrefix + profileId.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Profile].self, from: data) else {
            // Create default profile if none exist
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

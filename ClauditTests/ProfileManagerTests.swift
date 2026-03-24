import XCTest
@testable import Claudit

@MainActor
final class ProfileManagerTests: XCTestCase {

    // MARK: - Profile Model

    func testProfileDefaultValues() {
        let profile = Profile(name: "Test")
        XCTAssertEqual(profile.name, "Test")
        XCTAssertFalse(profile.isActive)
        XCTAssertFalse(profile.autoSwitchOnLimit)
        XCTAssertEqual(profile.quotaSource, QuotaSource.rateLimitHeaders.rawValue)
        XCTAssertNil(profile.claudeConfigDir)
        XCTAssertNil(profile.claudeOrgId)
        XCTAssertNil(profile.consoleOrgId)
    }

    func testProfileCodable() throws {
        let profile = Profile(
            name: "Work",
            isActive: true,
            autoSwitchOnLimit: true,
            quotaSource: "OAuth API",
            claudeConfigDir: "/custom/.claude",
            claudeOrgId: "org-123",
            consoleOrgId: "console-456"
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.name, "Work")
        XCTAssertTrue(decoded.isActive)
        XCTAssertTrue(decoded.autoSwitchOnLimit)
        XCTAssertEqual(decoded.quotaSource, "OAuth API")
        XCTAssertEqual(decoded.claudeConfigDir, "/custom/.claude")
        XCTAssertEqual(decoded.claudeOrgId, "org-123")
        XCTAssertEqual(decoded.consoleOrgId, "console-456")
    }

    func testProfileEquality() {
        let id = UUID()
        let date = Date()
        let p1 = Profile(id: id, name: "Test", createdAt: date)
        let p2 = Profile(id: id, name: "Test", createdAt: date)
        let p3 = Profile(name: "Test") // different UUID
        XCTAssertEqual(p1, p2)
        XCTAssertNotEqual(p1, p3)
    }

    // MARK: - ProfileManager

    func testManagerHasDefaultProfile() {
        let manager = ProfileManager()
        XCTAssertFalse(manager.profiles.isEmpty)
        XCTAssertNotNil(manager.activeProfileId)
        XCTAssertNotNil(manager.activeProfile)
    }

    func testAddProfile() {
        let manager = ProfileManager()
        let initialCount = manager.profiles.count
        let profile = manager.addProfile(name: "Work")
        XCTAssertEqual(manager.profiles.count, initialCount + 1)
        XCTAssertEqual(profile.name, "Work")
    }

    func testRenameProfile() {
        let manager = ProfileManager()
        let profile = manager.addProfile(name: "Old Name")
        manager.renameProfile(profile.id, to: "New Name")
        let updated = manager.profiles.first { $0.id == profile.id }
        XCTAssertEqual(updated?.name, "New Name")
    }

    func testSwitchProfile() {
        let manager = ProfileManager()
        let p1 = manager.addProfile(name: "Profile 1")
        let p2 = manager.addProfile(name: "Profile 2")

        manager.switchTo(p2.id)
        XCTAssertEqual(manager.activeProfileId, p2.id)
        XCTAssertTrue(manager.profiles.first { $0.id == p2.id }!.isActive)
        XCTAssertFalse(manager.profiles.first { $0.id == p1.id }!.isActive)
    }

    func testDeleteProfile() {
        let manager = ProfileManager()
        let p2 = manager.addProfile(name: "To Delete")
        let countBefore = manager.profiles.count

        manager.deleteProfile(p2.id)
        XCTAssertEqual(manager.profiles.count, countBefore - 1)
        XCTAssertNil(manager.profiles.first { $0.id == p2.id })
    }

    func testCannotDeleteLastProfile() {
        let manager = ProfileManager()
        // Remove all but first
        while manager.profiles.count > 1 {
            manager.deleteProfile(manager.profiles.last!.id)
        }
        let lastId = manager.profiles.first!.id
        manager.deleteProfile(lastId)
        XCTAssertEqual(manager.profiles.count, 1, "Cannot delete the last profile")
    }

    func testAutoSwitchToNext() {
        let manager = ProfileManager()
        // Ensure clean state: remove any extra profiles with autoSwitch enabled
        for p in manager.profiles where p.autoSwitchOnLimit {
            var updated = p
            updated.autoSwitchOnLimit = false
            manager.updateProfile(updated)
        }

        let initial = manager.profiles.first!
        manager.switchTo(initial.id)

        var p2 = manager.addProfile(name: "AutoBackup")
        p2.autoSwitchOnLimit = true
        manager.updateProfile(p2)

        let switched = manager.autoSwitchToNext()
        XCTAssertNotNil(switched)
        XCTAssertEqual(switched?.id, p2.id)
        XCTAssertEqual(manager.activeProfileId, p2.id)

        // Cleanup
        manager.switchTo(initial.id)
        manager.deleteProfile(p2.id)
    }

    func testAutoSwitchReturnsNilWhenNoEligible() {
        let manager = ProfileManager()
        // Ensure clean state: remove any autoSwitch flags
        for p in manager.profiles where p.autoSwitchOnLimit {
            var updated = p
            updated.autoSwitchOnLimit = false
            manager.updateProfile(updated)
        }

        let p2 = manager.addProfile(name: "NoAutoSwitch")
        XCTAssertFalse(p2.autoSwitchOnLimit)

        manager.switchTo(manager.profiles.first!.id)
        let switched = manager.autoSwitchToNext()
        XCTAssertNil(switched)

        // Cleanup
        manager.deleteProfile(p2.id)
    }

    func testHasMultipleProfiles() {
        let manager = ProfileManager()
        // Start with default profile
        if manager.profiles.count == 1 {
            XCTAssertFalse(manager.hasMultipleProfiles)
        }
        manager.addProfile(name: "Second")
        XCTAssertTrue(manager.hasMultipleProfiles)
    }

    func testUpdateProfile() {
        let manager = ProfileManager()
        var profile = manager.addProfile(name: "Original")
        profile.autoSwitchOnLimit = true
        profile.claudeConfigDir = "/custom"
        manager.updateProfile(profile)

        let updated = manager.profiles.first { $0.id == profile.id }
        XCTAssertTrue(updated!.autoSwitchOnLimit)
        XCTAssertEqual(updated!.claudeConfigDir, "/custom")
    }

    // MARK: - ProfileCredentialKey

    func testCredentialKeyRawValues() {
        XCTAssertEqual(ProfileCredentialKey.claudeSessionKey.rawValue, "claudeSessionKey")
        XCTAssertEqual(ProfileCredentialKey.consoleSessionKey.rawValue, "consoleSessionKey")
    }

    func testCredentialKeyAllCases() {
        XCTAssertEqual(ProfileCredentialKey.allCases.count, 2)
    }
}

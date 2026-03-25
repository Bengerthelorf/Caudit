import XCTest
@testable import Claudit

@MainActor
final class ProfileManagerTests: XCTestCase {

    /// Create a ProfileManager with isolated temporary storage to avoid polluting user data.
    private func makeTestManager() -> ProfileManager {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudit-test-\(UUID().uuidString)")
            .appendingPathComponent("profiles.json")
        try? FileManager.default.createDirectory(
            at: tempURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return ProfileManager(storageURL: tempURL)
    }

    // MARK: - Profile Model

    func testProfileDefaultValues() {
        let profile = Profile(name: "Test")
        XCTAssertEqual(profile.name, "Test")
        XCTAssertFalse(profile.isActive)
        XCTAssertFalse(profile.autoSwitchOnLimit)
        XCTAssertEqual(profile.quotaSource, QuotaSource.rateLimitHeaders.rawValue)
    }

    func testProfileCodable() throws {
        let profile = Profile(
            name: "Work",
            isActive: true,
            autoSwitchOnLimit: true,
            quotaSource: "OAuth API"
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.name, "Work")
        XCTAssertTrue(decoded.isActive)
        XCTAssertTrue(decoded.autoSwitchOnLimit)
        XCTAssertEqual(decoded.quotaSource, "OAuth API")
    }

    func testProfileEquality() {
        let id = UUID()
        let date = Date()
        let p1 = Profile(id: id, name: "Test", createdAt: date)
        let p2 = Profile(id: id, name: "Test", createdAt: date)
        let p3 = Profile(name: "Test")
        XCTAssertEqual(p1, p2)
        XCTAssertNotEqual(p1, p3)
    }

    // MARK: - ProfileManager (isolated storage)

    func testManagerHasDefaultProfile() {
        let manager = makeTestManager()
        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertNotNil(manager.activeProfileId)
        XCTAssertEqual(manager.activeProfile?.name, "Default")
    }

    func testAddProfile() {
        let manager = makeTestManager()
        let profile = manager.addProfile(name: "Work")
        XCTAssertEqual(manager.profiles.count, 2)
        XCTAssertEqual(profile.name, "Work")
    }

    func testRenameProfile() {
        let manager = makeTestManager()
        let profile = manager.addProfile(name: "Old Name")
        manager.renameProfile(profile.id, to: "New Name")
        let updated = manager.profiles.first { $0.id == profile.id }
        XCTAssertEqual(updated?.name, "New Name")
    }

    func testSwitchProfile() {
        let manager = makeTestManager()
        let p2 = manager.addProfile(name: "Second")

        manager.switchTo(p2.id)
        XCTAssertEqual(manager.activeProfileId, p2.id)
        XCTAssertTrue(manager.profiles.first { $0.id == p2.id }!.isActive)
    }

    func testDeleteProfile() {
        let manager = makeTestManager()
        let p2 = manager.addProfile(name: "To Delete")
        XCTAssertEqual(manager.profiles.count, 2)

        manager.deleteProfile(p2.id)
        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertNil(manager.profiles.first { $0.id == p2.id })
    }

    func testCannotDeleteLastProfile() {
        let manager = makeTestManager()
        let lastId = manager.profiles.first!.id
        manager.deleteProfile(lastId)
        XCTAssertEqual(manager.profiles.count, 1)
    }

    func testAutoSwitchToNext() {
        let manager = makeTestManager()
        var p2 = manager.addProfile(name: "Backup")
        p2.autoSwitchOnLimit = true
        manager.updateProfile(p2)

        let switched = manager.autoSwitchToNext()
        XCTAssertNotNil(switched)
        XCTAssertEqual(switched?.id, p2.id)
    }

    func testAutoSwitchReturnsNilWhenNoEligible() {
        let manager = makeTestManager()
        let _ = manager.addProfile(name: "NoAutoSwitch")
        let switched = manager.autoSwitchToNext()
        XCTAssertNil(switched)
    }

    func testHasMultipleProfiles() {
        let manager = makeTestManager()
        XCTAssertFalse(manager.hasMultipleProfiles)
        manager.addProfile(name: "Second")
        XCTAssertTrue(manager.hasMultipleProfiles)
    }

    // MARK: - ProfileCredentialKey

    func testCredentialKeyRawValues() {
        XCTAssertEqual(ProfileCredentialKey.claudeSessionKey.rawValue, "claudeSessionKey")
        XCTAssertEqual(ProfileCredentialKey.consoleSessionKey.rawValue, "consoleSessionKey")
    }
}

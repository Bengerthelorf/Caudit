import XCTest
@testable import Claudit

@MainActor
final class AutoStartSessionServiceTests: XCTestCase {

    // MARK: - AutoStartError

    func testAutoStartErrorDescriptions() {
        XCTAssertNotNil(AutoStartError.noSession.errorDescription)
        XCTAssertNotNil(AutoStartError.sessionExpired.errorDescription)
        XCTAssertNotNil(AutoStartError.invalidResponse.errorDescription)
        XCTAssertNotNil(AutoStartError.httpError(500).errorDescription)
    }

    func testAutoStartErrorEquality() {
        XCTAssertEqual(AutoStartError.noSession, AutoStartError.noSession)
        XCTAssertEqual(AutoStartError.httpError(404), AutoStartError.httpError(404))
        XCTAssertNotEqual(AutoStartError.httpError(404), AutoStartError.httpError(500))
        XCTAssertNotEqual(AutoStartError.noSession, AutoStartError.sessionExpired)
    }

    // MARK: - Service State

    func testServiceDefaultDisabled() {
        // Clear the UserDefaults key to ensure clean state
        UserDefaults.standard.removeObject(forKey: "autoStartSessionEnabled")
        let service = AutoStartSessionService()
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(service.isRunning)
        XCTAssertNil(service.lastAttempt)
        XCTAssertNil(service.lastResult)
    }

    func testServicePersistsEnabledState() {
        let service = AutoStartSessionService()
        service.isEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "autoStartSessionEnabled"))
        service.isEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "autoStartSessionEnabled"))
    }

    func testOnQuotaUpdateIgnoredWhenDisabled() {
        let service = AutoStartSessionService()
        service.isEnabled = false
        service.onQuotaUpdate(fiveHourUtilization: 0)
        // Should not start since disabled
        XCTAssertFalse(service.isRunning)
    }

    func testOnQuotaUpdateIgnoredWhenNotZero() {
        let service = AutoStartSessionService()
        service.isEnabled = true
        service.onQuotaUpdate(fiveHourUtilization: 50.0)
        // Should not start since utilization > 0
        XCTAssertFalse(service.isRunning)
        service.isEnabled = false // cleanup
    }
}

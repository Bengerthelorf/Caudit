import XCTest
@testable import Claudit

final class NotificationServiceTests: XCTestCase {

    // MARK: - Threshold Firing Logic

    func testSingleThresholdFires() {
        let result = NotificationService.thresholdsToFire(
            current: 80,
            previousLevel: 70,
            enabledThresholds: [75, 90, 95]
        )
        XCTAssertEqual(result, [75])
    }

    func testMultipleThresholdsFire() {
        let result = NotificationService.thresholdsToFire(
            current: 96,
            previousLevel: 70,
            enabledThresholds: [75, 90, 95]
        )
        XCTAssertEqual(result, [75, 90, 95])
    }

    func testNoThresholdFiresWhenBelowAll() {
        let result = NotificationService.thresholdsToFire(
            current: 50,
            previousLevel: 40,
            enabledThresholds: [75, 90, 95]
        )
        XCTAssertEqual(result, [])
    }

    func testNoThresholdFiresWhenAlreadyAbove() {
        // Already notified for 75, now at 80 — shouldn't re-fire 75
        let result = NotificationService.thresholdsToFire(
            current: 80,
            previousLevel: 76,
            enabledThresholds: [75, 90, 95]
        )
        XCTAssertEqual(result, [])
    }

    func testThresholdFiresOnExactValue() {
        let result = NotificationService.thresholdsToFire(
            current: 75,
            previousLevel: 74,
            enabledThresholds: [75]
        )
        XCTAssertEqual(result, [75])
    }

    func testEmptyThresholdsNeverFires() {
        let result = NotificationService.thresholdsToFire(
            current: 100,
            previousLevel: 0,
            enabledThresholds: []
        )
        XCTAssertEqual(result, [])
    }

    func testResultIsSorted() {
        let result = NotificationService.thresholdsToFire(
            current: 100,
            previousLevel: 0,
            enabledThresholds: [95, 50, 75, 90]
        )
        XCTAssertEqual(result, [50, 75, 90, 95])
    }

    // MARK: - Session Reset Detection

    func testSessionResetDetected() {
        XCTAssertTrue(NotificationService.isSessionReset(current: 0, previousLevel: 50))
    }

    func testSessionResetNotDetectedWhenStillAboveZero() {
        XCTAssertFalse(NotificationService.isSessionReset(current: 10, previousLevel: 50))
    }

    func testSessionResetNotDetectedWhenAlreadyZero() {
        XCTAssertFalse(NotificationService.isSessionReset(current: 0, previousLevel: 0))
    }

    func testSessionResetNotDetectedWhenRising() {
        XCTAssertFalse(NotificationService.isSessionReset(current: 30, previousLevel: 0))
    }
}

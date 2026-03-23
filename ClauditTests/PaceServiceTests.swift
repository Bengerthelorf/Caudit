import XCTest
@testable import Claudit

final class PaceServiceTests: XCTestCase {

    // MARK: - Classification

    func testClassifyComfortable() {
        XCTAssertEqual(PaceService.classify(0), .comfortable)
        XCTAssertEqual(PaceService.classify(30), .comfortable)
        XCTAssertEqual(PaceService.classify(49.9), .comfortable)
    }

    func testClassifyOnTrack() {
        XCTAssertEqual(PaceService.classify(50), .onTrack)
        XCTAssertEqual(PaceService.classify(74.9), .onTrack)
    }

    func testClassifyWarming() {
        XCTAssertEqual(PaceService.classify(75), .warming)
        XCTAssertEqual(PaceService.classify(89.9), .warming)
    }

    func testClassifyPressing() {
        XCTAssertEqual(PaceService.classify(90), .pressing)
        XCTAssertEqual(PaceService.classify(99.9), .pressing)
    }

    func testClassifyCritical() {
        XCTAssertEqual(PaceService.classify(100), .critical)
        XCTAssertEqual(PaceService.classify(119.9), .critical)
    }

    func testClassifyRunaway() {
        XCTAssertEqual(PaceService.classify(120), .runaway)
        XCTAssertEqual(PaceService.classify(200), .runaway)
    }

    // MARK: - Pace Calculation

    func testPaceNilWhenInsufficientElapsed() {
        let result = PaceService.calculatePace(usedPercentage: 50, elapsedFraction: 0.02)
        XCTAssertNil(result, "Should return nil when elapsed < 3%")
    }

    func testPaceAtMinimumElapsed() {
        let result = PaceService.calculatePace(usedPercentage: 3, elapsedFraction: 0.03)
        XCTAssertNotNil(result)
        // 3% / 0.03 = 100% projected → critical (100-120% range)
        XCTAssertEqual(result, .critical)
    }

    func testPaceComfortable() {
        // 10% used, 50% elapsed → projected 20%
        let result = PaceService.calculatePace(usedPercentage: 10, elapsedFraction: 0.5)
        XCTAssertEqual(result, .comfortable)
    }

    func testPaceRunaway() {
        // 60% used, 25% elapsed → projected 240%
        let result = PaceService.calculatePace(usedPercentage: 60, elapsedFraction: 0.25)
        XCTAssertEqual(result, .runaway)
    }

    func testPaceOnTrack() {
        // 50% used, 80% elapsed → projected 62.5%
        let result = PaceService.calculatePace(usedPercentage: 50, elapsedFraction: 0.8)
        XCTAssertEqual(result, .onTrack)
    }

    func testZeroUsageIsComfortable() {
        let result = PaceService.calculatePace(usedPercentage: 0, elapsedFraction: 0.5)
        XCTAssertEqual(result, .comfortable)
    }

    // MARK: - Elapsed Fraction Calculation

    func testFiveHourElapsedFractionNilReset() {
        let result = PaceService.fiveHourElapsedFraction(resetAt: nil)
        XCTAssertEqual(result, 0)
    }

    func testFiveHourElapsedFractionFuture() {
        // 2.5 hours remaining → 50% elapsed
        let resetAt = Date().addingTimeInterval(2.5 * 3600)
        let result = PaceService.fiveHourElapsedFraction(resetAt: resetAt)
        XCTAssertEqual(result, 0.5, accuracy: 0.01)
    }

    func testFiveHourElapsedFractionPast() {
        // Already past
        let resetAt = Date().addingTimeInterval(-100)
        let result = PaceService.fiveHourElapsedFraction(resetAt: resetAt)
        XCTAssertEqual(result, 0)
    }

    func testSevenDayElapsedFractionNilReset() {
        let result = PaceService.sevenDayElapsedFraction(resetAt: nil)
        XCTAssertEqual(result, 0)
    }

    func testSevenDayElapsedFractionHalfway() {
        // 3.5 days remaining → 50% elapsed
        let resetAt = Date().addingTimeInterval(3.5 * 24 * 3600)
        let result = PaceService.sevenDayElapsedFraction(resetAt: resetAt)
        XCTAssertEqual(result, 0.5, accuracy: 0.01)
    }

    // MARK: - PaceStatus Properties

    func testAllStatusesHaveUniqueLabels() {
        let labels = PaceStatus.allCases.map(\.label)
        XCTAssertEqual(labels.count, Set(labels).count)
    }

    func testAllStatusesHaveColors() {
        // Just verify they don't crash
        for status in PaceStatus.allCases {
            _ = status.color
        }
    }
}

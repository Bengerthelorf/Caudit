import XCTest
@testable import Claudit

final class StatuslineServiceTests: XCTestCase {

    // MARK: - Progress Bar

    func testProgressBarEmpty() {
        let bar = StatuslineService.progressBar(percentage: 0, segments: 10)
        XCTAssertEqual(bar, "░░░░░░░░░░")
    }

    func testProgressBarFull() {
        let bar = StatuslineService.progressBar(percentage: 100, segments: 10)
        XCTAssertEqual(bar, "▓▓▓▓▓▓▓▓▓▓")
    }

    func testProgressBarHalf() {
        let bar = StatuslineService.progressBar(percentage: 50, segments: 10)
        XCTAssertEqual(bar, "▓▓▓▓▓░░░░░")
    }

    func testProgressBarCustomSegments() {
        let bar = StatuslineService.progressBar(percentage: 60, segments: 5)
        XCTAssertEqual(bar, "▓▓▓░░")
    }

    func testProgressBarClampsAbove100() {
        let bar = StatuslineService.progressBar(percentage: 150, segments: 10)
        XCTAssertEqual(bar, "▓▓▓▓▓▓▓▓▓▓")
    }

    func testProgressBarClampsNegative() {
        let bar = StatuslineService.progressBar(percentage: -10, segments: 10)
        XCTAssertEqual(bar, "░░░░░░░░░░")
    }

    // MARK: - Cache Content Formatting

    func testFormatCacheContentDefault() {
        let config = StatuslineService.Config(
            enabled: true,
            showUsagePercent: true,
            showProgressBar: true,
            showResetTime: true,
            showPaceLabel: true,
            barSegments: 10
        )
        let result = StatuslineService.formatCacheContent(
            sessionPercent: 75,
            weeklyPercent: 30,
            config: config
        )
        XCTAssertTrue(result.contains("75%"))
        XCTAssertTrue(result.contains("▓"))
        XCTAssertTrue(result.contains("7d:30%"))
        XCTAssertTrue(result.contains("On Track"))
        XCTAssertTrue(result.contains("⏱"))
    }

    func testFormatCacheContentNoProgressBar() {
        let config = StatuslineService.Config(
            enabled: true,
            showUsagePercent: true,
            showProgressBar: false,
            barSegments: 10
        )
        let result = StatuslineService.formatCacheContent(
            sessionPercent: 50,
            weeklyPercent: 20,
            config: config
        )
        XCTAssertTrue(result.contains("50%"))
        XCTAssertFalse(result.contains("▓"))
    }

    func testFormatCacheContentNoUsagePercent() {
        let config = StatuslineService.Config(
            enabled: true,
            showUsagePercent: false,
            showProgressBar: true,
            barSegments: 5
        )
        let result = StatuslineService.formatCacheContent(
            sessionPercent: 40,
            weeklyPercent: 10,
            config: config
        )
        XCTAssertTrue(result.contains("▓▓░░░"))
        XCTAssertTrue(result.contains("7d:10%"))
    }

    func testFormatCacheContentNoPace() {
        let config = StatuslineService.Config(
            enabled: true,
            showPaceLabel: false
        )
        let result = StatuslineService.formatCacheContent(
            sessionPercent: 50,
            weeklyPercent: 20,
            config: config
        )
        XCTAssertFalse(result.contains("On Track"))
    }

    func testFormatCacheContent12HourTime() {
        let config = StatuslineService.Config(
            enabled: true,
            use24HourTime: false
        )
        let result = StatuslineService.formatCacheContent(
            sessionPercent: 50,
            weeklyPercent: 20,
            config: config
        )
        XCTAssertTrue(result.contains("2:30PM"))
    }

    // MARK: - Config

    func testConfigDefaultValues() {
        let config = StatuslineService.Config()
        XCTAssertFalse(config.enabled)
        XCTAssertTrue(config.showUsagePercent)
        XCTAssertTrue(config.showProgressBar)
        XCTAssertTrue(config.showResetTime)
        XCTAssertTrue(config.showPaceLabel)
        XCTAssertTrue(config.use24HourTime)
        XCTAssertEqual(config.barSegments, 10)
    }

    func testConfigCodable() throws {
        let config = StatuslineService.Config(
            enabled: true,
            showUsagePercent: false,
            showProgressBar: true,
            showResetTime: false,
            showPaceLabel: true,
            use24HourTime: false,
            barSegments: 15
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(StatuslineService.Config.self, from: data)
        XCTAssertEqual(config, decoded)
    }
}

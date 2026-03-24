import XCTest
@testable import Claudit

final class MenuBarConfigTests: XCTestCase {

    func testDefaultConfigShowsCostOnly() {
        let config = MenuBarConfig()
        let text = config.formatText(
            todayCost: 4.20, quotaPercent: nil, pace: nil,
            resetTimeRemaining: nil, weeklyPercent: nil
        )
        XCTAssertEqual(text, "$4.20")
    }

    func testAllComponentsEnabled() {
        var config = MenuBarConfig()
        config.showCost = true
        config.showQuotaPercent = true
        config.showPace = true
        config.showResetTime = true
        config.showWeeklyPercent = true

        let text = config.formatText(
            todayCost: 1.50, quotaPercent: 65, pace: "On Track",
            resetTimeRemaining: 7200, weeklyPercent: 30
        )
        XCTAssertTrue(text.contains("$1.50"))
        XCTAssertTrue(text.contains("65%"))
        XCTAssertTrue(text.contains("On Track"))
        XCTAssertTrue(text.contains("⏱2h0m"))
        XCTAssertTrue(text.contains("7d:30%"))
    }

    func testNothingEnabled() {
        var config = MenuBarConfig()
        config.showCost = false

        let text = config.formatText(
            todayCost: 5.0, quotaPercent: nil, pace: nil,
            resetTimeRemaining: nil, weeklyPercent: nil
        )
        XCTAssertEqual(text, "--")
    }

    func testQuotaPercentOnly() {
        var config = MenuBarConfig()
        config.showCost = false
        config.showQuotaPercent = true

        let text = config.formatText(
            todayCost: nil, quotaPercent: 87, pace: nil,
            resetTimeRemaining: nil, weeklyPercent: nil
        )
        XCTAssertEqual(text, "87%")
    }

    func testCostFormatting() {
        let config = MenuBarConfig()

        XCTAssertEqual(
            config.formatText(todayCost: 0.005, quotaPercent: nil, pace: nil, resetTimeRemaining: nil, weeklyPercent: nil),
            "$0.00"
        )
        XCTAssertEqual(
            config.formatText(todayCost: 15.0, quotaPercent: nil, pace: nil, resetTimeRemaining: nil, weeklyPercent: nil),
            "$15"
        )
    }

    func testResetTimeFormatting() {
        var config = MenuBarConfig()
        config.showCost = false
        config.showResetTime = true

        let text = config.formatText(
            todayCost: nil, quotaPercent: nil, pace: nil,
            resetTimeRemaining: 5400, weeklyPercent: nil
        )
        XCTAssertEqual(text, "⏱1h30m")
    }

    func testMinutesOnlyResetTime() {
        var config = MenuBarConfig()
        config.showCost = false
        config.showResetTime = true

        let text = config.formatText(
            todayCost: nil, quotaPercent: nil, pace: nil,
            resetTimeRemaining: 900, weeklyPercent: nil
        )
        XCTAssertEqual(text, "⏱15m")
    }

    func testCodable() throws {
        var config = MenuBarConfig()
        config.showPace = true
        config.showWeeklyPercent = true

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MenuBarConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }
}

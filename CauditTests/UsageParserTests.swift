import XCTest
@testable import Caudit

final class UsageParserTests: XCTestCase {

    // MARK: - allTimeDailyMap key uniqueness (cross-year)

    func testAllTimeDailyMapDoesNotCollideAcrossYears() {
        let parser = UsageParser()
        let calendar = Calendar.current

        // Create records on the same month/day but different years
        let date2025 = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 12))!
        let date2026 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 17, hour: 12))!

        let records = [
            makeRecord(timestamp: date2025, cost: 1.00),
            makeRecord(timestamp: date2026, cost: 2.00),
        ]

        let result = parser.aggregate(records: records)

        // Should have 2 separate daily entries, not 1 merged entry
        let march17entries = result.allTimeDailyHistory.filter {
            calendar.component(.day, from: $0.date) == 17 &&
            calendar.component(.month, from: $0.date) == 3
        }

        XCTAssertEqual(march17entries.count, 2, "Same month/day in different years must be separate entries")

        let costs = march17entries.map(\.totalCost).sorted()
        XCTAssertEqual(costs, [1.00, 2.00], "Each year's cost should be independent")
    }

    // MARK: - dayHourMap key uniqueness

    func testDayHourMapDoesNotCollideAcrossYears() {
        let parser = UsageParser()
        let calendar = Calendar.current

        let date2025 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 15, hour: 10))!
        let date2026 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 10))!

        let records = [
            makeRecord(timestamp: date2025, cost: 1.00),
            makeRecord(timestamp: date2026, cost: 3.00),
        ]

        let result = parser.aggregate(records: records)

        // dayHourlyBreakdown should have 2 separate entries
        let june15entries = result.dayHourlyBreakdown.filter {
            calendar.component(.day, from: $0.date) == 15 &&
            calendar.component(.month, from: $0.date) == 6
        }

        XCTAssertEqual(june15entries.count, 2, "Same month/day in different years must produce separate dayHourly entries")
    }

    // MARK: - 7-day dailyHistory always has 7 entries

    func testDailyHistoryAlwaysHas7Days() {
        let parser = UsageParser()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Only one record today
        let records = [makeRecord(timestamp: today, cost: 5.00)]

        let result = parser.aggregate(records: records)

        XCTAssertEqual(result.dailyHistory.count, 7, "dailyHistory should always cover 7 days")
        XCTAssertEqual(result.dailyHistory.last?.totalCost, 5.00)
    }

    // MARK: - todayHourlyHistory always has 24 entries

    func testTodayHourlyHistoryAlwaysHas24Entries() {
        let parser = UsageParser()
        let result = parser.aggregate(records: [])
        XCTAssertEqual(result.todayHourlyHistory.count, 24)
    }

    // MARK: - ShellEscape

    func testShellEscapeTildeExpansion() {
        XCTAssertEqual(ShellEscape.path("~/.claude"), "~/'.claude'")
        XCTAssertEqual(ShellEscape.path("~/path/to/dir"), "~/'path/to/dir'")
        XCTAssertEqual(ShellEscape.path("~"), "~")
    }

    func testShellEscapeAbsolutePath() {
        XCTAssertEqual(ShellEscape.path("/usr/local/bin"), "'/usr/local/bin'")
    }

    func testShellEscapeSingleQuoteInPath() {
        XCTAssertEqual(ShellEscape.path("/tmp/it's here"), "'/tmp/it'\\''s here'")
    }

    func testShellEscapeNoInjection() {
        let malicious = "~/.claude; rm -rf /"
        let escaped = ShellEscape.path(malicious)
        XCTAssertEqual(escaped, "~/'.claude; rm -rf /'")
        // The semicolon is safely inside single quotes
    }

    // MARK: - Helpers

    private func makeRecord(
        timestamp: Date,
        cost: Double,
        model: String = "claude-sonnet-4",
        project: String = "test",
        source: String = "Local"
    ) -> UsageRecord {
        UsageRecord(
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            model: model,
            timestamp: timestamp,
            cost: cost,
            project: project,
            source: source,
            sessionId: UUID().uuidString,
            slug: "",
            toolCalls: [],
            projectDir: project
        )
    }
}

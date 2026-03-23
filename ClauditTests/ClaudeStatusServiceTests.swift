import XCTest
@testable import Claudit

final class ClaudeStatusServiceTests: XCTestCase {

    // MARK: - JSON Parsing

    func testParseOperationalStatus() throws {
        let json = """
        {
            "page": {"updated_at": "2026-03-23T10:00:00Z"},
            "status": {"indicator": "none", "description": "All Systems Operational"}
        }
        """.data(using: .utf8)!

        let status = try ClaudeStatusService.parse(json)
        XCTAssertEqual(status.indicator, .none)
        XCTAssertEqual(status.description, "All Systems Operational")
        XCTAssertNotNil(status.updatedAt)
    }

    func testParseMinorIndicator() throws {
        let json = """
        {"page": {}, "status": {"indicator": "minor", "description": "Degraded Performance"}}
        """.data(using: .utf8)!

        let status = try ClaudeStatusService.parse(json)
        XCTAssertEqual(status.indicator, .minor)
        XCTAssertEqual(status.description, "Degraded Performance")
    }

    func testParseMajorIndicator() throws {
        let json = """
        {"page": {}, "status": {"indicator": "major", "description": "Partial System Outage"}}
        """.data(using: .utf8)!

        let status = try ClaudeStatusService.parse(json)
        XCTAssertEqual(status.indicator, .major)
    }

    func testParseCriticalIndicator() throws {
        let json = """
        {"page": {}, "status": {"indicator": "critical", "description": "Major System Outage"}}
        """.data(using: .utf8)!

        let status = try ClaudeStatusService.parse(json)
        XCTAssertEqual(status.indicator, .critical)
    }

    func testParseUnknownIndicatorFallback() throws {
        let json = """
        {"page": {}, "status": {"indicator": "maintenance", "description": "Under Maintenance"}}
        """.data(using: .utf8)!

        let status = try ClaudeStatusService.parse(json)
        XCTAssertEqual(status.indicator, .unknown)
        XCTAssertEqual(status.description, "Under Maintenance")
    }

    func testParseMissingIndicatorDefaultsToUnknown() throws {
        let json = """
        {"page": {}, "status": {"description": "Something"}}
        """.data(using: .utf8)!

        let status = try ClaudeStatusService.parse(json)
        XCTAssertEqual(status.indicator, .unknown)
    }

    func testParseMissingStatusThrows() {
        let json = """
        {"page": {}}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try ClaudeStatusService.parse(json))
    }

    func testParseUpdatedAtDate() throws {
        let json = """
        {"page": {"updated_at": "2026-03-23T15:30:00Z"}, "status": {"indicator": "none", "description": "OK"}}
        """.data(using: .utf8)!

        let status = try ClaudeStatusService.parse(json)
        XCTAssertNotNil(status.updatedAt)

        let calendar = Calendar(identifier: .gregorian)
        var comps = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: status.updatedAt!)
        XCTAssertEqual(comps.hour, 15)
        XCTAssertEqual(comps.minute, 30)
    }

    func testParseMissingUpdatedAtReturnsNil() throws {
        let json = """
        {"page": {}, "status": {"indicator": "none", "description": "OK"}}
        """.data(using: .utf8)!

        let status = try ClaudeStatusService.parse(json)
        XCTAssertNil(status.updatedAt)
    }

    // MARK: - Indicator Properties

    func testIndicatorLabels() {
        XCTAssertEqual(ClaudeStatus.Indicator.none.label, "Operational")
        XCTAssertEqual(ClaudeStatus.Indicator.minor.label, "Minor Issues")
        XCTAssertEqual(ClaudeStatus.Indicator.major.label, "Major Outage")
        XCTAssertEqual(ClaudeStatus.Indicator.critical.label, "Critical Outage")
        XCTAssertEqual(ClaudeStatus.Indicator.unknown.label, "Unknown")
    }
}

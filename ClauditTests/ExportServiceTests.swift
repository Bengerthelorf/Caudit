import XCTest
@testable import Claudit

final class ExportServiceTests: XCTestCase {

    private func makeRecord(
        project: String = "test-project",
        model: String = "claude-sonnet-4-5",
        source: String = "Local",
        inputTokens: Int = 100,
        outputTokens: Int = 50,
        cacheRead: Int = 10,
        cacheWrite: Int = 5,
        cost: Double = 0.001234,
        timestamp: Date = Date(timeIntervalSince1970: 1711200000)
    ) -> UsageRecord {
        UsageRecord(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheWrite,
            model: model,
            timestamp: timestamp,
            cost: cost,
            project: project,
            source: source,
            sessionId: "sess-1",
            slug: "test",
            toolCalls: [],
            projectDir: "/test"
        )
    }

    // MARK: - CSV Export

    func testCSVHeader() {
        let csv = ExportService.toCSV([])
        XCTAssertEqual(csv, "Timestamp,Project,Model,Source,Session ID,Input Tokens,Output Tokens,Cache Read,Cache Write,Cost")
    }

    func testCSVSingleRecord() {
        let records = [makeRecord()]
        let csv = ExportService.toCSV(records)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2) // header + 1 row
        let row = String(lines[1])
        XCTAssertTrue(row.contains("test-project"))
        XCTAssertTrue(row.contains("claude-sonnet-4-5"))
        XCTAssertTrue(row.contains("Local"))
        XCTAssertTrue(row.contains("100"))
        XCTAssertTrue(row.contains("50"))
    }

    func testCSVEscapesCommasInProjectName() {
        let records = [makeRecord(project: "project,with,commas")]
        let csv = ExportService.toCSV(records)
        XCTAssertTrue(csv.contains("\"project,with,commas\""))
    }

    func testCSVEscapesQuotesInProjectName() {
        let records = [makeRecord(project: "project\"quoted\"")]
        let csv = ExportService.toCSV(records)
        XCTAssertTrue(csv.contains("\"project\"\"quoted\"\"\""))
    }

    func testCSVMultipleRecords() {
        let records = [
            makeRecord(project: "proj-a"),
            makeRecord(project: "proj-b"),
            makeRecord(project: "proj-c"),
        ]
        let csv = ExportService.toCSV(records)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 4) // header + 3 rows
    }

    // MARK: - JSON Export

    func testJSONEmptyRecords() {
        let json = ExportService.toJSON([])
        XCTAssertEqual(json.trimmingCharacters(in: .whitespacesAndNewlines), "[\n\n]")
    }

    func testJSONSingleRecord() throws {
        let records = [makeRecord()]
        let json = ExportService.toJSON(records)
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(parsed.count, 1)
        let entry = parsed[0]
        XCTAssertEqual(entry["project"] as? String, "test-project")
        XCTAssertEqual(entry["model"] as? String, "claude-sonnet-4-5")
        XCTAssertEqual(entry["input_tokens"] as? Int, 100)
        XCTAssertEqual(entry["output_tokens"] as? Int, 50)
        XCTAssertEqual(entry["cache_read_tokens"] as? Int, 10)
        XCTAssertEqual(entry["cache_write_tokens"] as? Int, 5)
    }

    func testJSONContainsTimestamp() throws {
        let records = [makeRecord()]
        let json = ExportService.toJSON(records)
        XCTAssertTrue(json.contains("timestamp"))
        // Should be ISO8601 format
        XCTAssertTrue(json.contains("2024-03-23"))
    }

    // MARK: - Format Selection

    func testExportFormatFileExtensions() {
        XCTAssertEqual(ExportFormat.json.fileExtension, "json")
        XCTAssertEqual(ExportFormat.csv.fileExtension, "csv")
    }

    func testExportRecordsDispatchesCorrectFormat() {
        let records = [makeRecord()]

        let jsonResult = ExportService.exportRecords(records, format: .json)
        XCTAssertTrue(jsonResult.hasPrefix("["))

        let csvResult = ExportService.exportRecords(records, format: .csv)
        XCTAssertTrue(csvResult.hasPrefix("Timestamp,"))
    }
}

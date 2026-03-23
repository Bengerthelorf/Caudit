import XCTest
@testable import Claudit

final class UsageHistoryServiceTests: XCTestCase {

    // MARK: - UsageSnapshot

    func testSnapshotEncodeDecode() throws {
        let snapshot = UsageSnapshot(
            timestamp: Date(timeIntervalSince1970: 1711200000),
            type: .session,
            percentage: 75.5,
            tokensUsed: 1000
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.percentage, 75.5)
        XCTAssertEqual(decoded.tokensUsed, 1000)
        XCTAssertEqual(decoded.type, .session)
    }

    func testSnapshotHasUniqueId() {
        let a = UsageSnapshot(type: .session, percentage: 50)
        let b = UsageSnapshot(type: .session, percentage: 50)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testSnapshotWeeklyType() throws {
        let snapshot = UsageSnapshot(type: .weekly, percentage: 30)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.type, .weekly)
    }

    // MARK: - HistoryTimeScale

    func testTimeScaleIntervals() {
        XCTAssertEqual(HistoryTimeScale.fiveHours.timeInterval, 5 * 3600)
        XCTAssertEqual(HistoryTimeScale.twentyFourHours.timeInterval, 24 * 3600)
        XCTAssertEqual(HistoryTimeScale.sevenDays.timeInterval, 7 * 24 * 3600)
        XCTAssertEqual(HistoryTimeScale.thirtyDays.timeInterval, 30 * 24 * 3600)
    }

    func testTimeScaleStepIsHalfOfInterval() {
        for scale in HistoryTimeScale.allCases {
            XCTAssertEqual(scale.stepInterval, scale.timeInterval / 2)
        }
    }

    // MARK: - SnapshotType

    func testSnapshotTypeRawValues() {
        XCTAssertEqual(SnapshotType.session.rawValue, "session")
        XCTAssertEqual(SnapshotType.weekly.rawValue, "weekly")
    }
}

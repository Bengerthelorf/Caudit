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
}

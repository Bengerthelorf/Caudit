import XCTest
@testable import Claudit

final class SystemEventServiceTests: XCTestCase {

    // MARK: - Debounce Logic

    func testFirstTriggerFiresImmediately() {
        let expectation = expectation(description: "refresh called")
        let service = SystemEventService(debounceInterval: 10) {
            expectation.fulfill()
        }
        service.triggerRefreshIfNeeded()
        wait(for: [expectation], timeout: 1)
        _ = service // keep alive
    }

    func testRapidTriggersAreDebounced() {
        var callCount = 0
        let service = SystemEventService(debounceInterval: 10) {
            callCount += 1
        }

        // Trigger 5 times rapidly — only the first should fire
        for _ in 0..<5 {
            service.triggerRefreshIfNeeded()
        }

        XCTAssertEqual(callCount, 1, "Rapid triggers within debounce interval should only fire once")
        _ = service
    }

    func testTriggerFiresAfterDebounceInterval() {
        var callCount = 0
        let service = SystemEventService(debounceInterval: 0.1) {
            callCount += 1
        }

        service.triggerRefreshIfNeeded()
        XCTAssertEqual(callCount, 1)

        // Wait for debounce to expire
        let expectation = expectation(description: "debounce expired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            service.triggerRefreshIfNeeded()
            XCTAssertEqual(callCount, 2, "Trigger should fire after debounce interval expires")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testZeroDebounceAllowsAllTriggers() {
        var callCount = 0
        let service = SystemEventService(debounceInterval: 0) {
            callCount += 1
        }

        service.triggerRefreshIfNeeded()
        service.triggerRefreshIfNeeded()
        service.triggerRefreshIfNeeded()

        XCTAssertEqual(callCount, 3, "Zero debounce should allow all triggers")
        _ = service
    }
}

import XCTest
@testable import Crest

final class BrowserProcessRecoveryTests: XCTestCase {
    func testStopsAfterTwoConsecutiveAutomaticReloads() {
        var recovery = BrowserProcessRecovery()

        XCTAssertEqual(recovery.recordTermination(), .reload)
        XCTAssertEqual(recovery.recordTermination(), .reload)
        XCTAssertEqual(recovery.recordTermination(), .showFailure)
        XCTAssertEqual(recovery.recordTermination(), .showFailure)
    }

    func testSuccessfulNavigationResetsTheCrashBudget() {
        var recovery = BrowserProcessRecovery()

        XCTAssertEqual(recovery.recordTermination(), .reload)
        XCTAssertEqual(recovery.recordTermination(), .reload)
        recovery.recordSuccessfulNavigation()

        XCTAssertEqual(recovery.recordTermination(), .reload)
    }

    func testManualRetryResetsTheCrashBudget() {
        var recovery = BrowserProcessRecovery()
        _ = recovery.recordTermination()
        _ = recovery.recordTermination()
        XCTAssertEqual(recovery.recordTermination(), .showFailure)

        recovery.reset()

        XCTAssertEqual(recovery.recordTermination(), .reload)
    }
}

import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionPopupBackgroundWarmUpTests: XCTestCase {
    func testPresentsAsSoonAsBackgroundContentReportsLoaded() {
        var reportLoaded: (@MainActor (Error?) -> Void)?
        let warmUp = BrowserExtensionPopupBackgroundWarmUp(
            deadline: .seconds(30)
        ) { loaded in
            reportLoaded = loaded
        }

        var outcomes: [BrowserExtensionPopupBackgroundWarmUp.Outcome] = []
        warmUp.prepare { outcomes.append($0) }
        XCTAssertEqual(
            outcomes.count,
            0,
            "The popup was presented before its background content loaded."
        )

        reportLoaded?(nil)
        guard case .loaded? = outcomes.first else {
            return XCTFail(
                "The background preparation did not report a successful load."
            )
        }
    }

    /// WebKit never calls `loadBackgroundContent`'s completion handler when
    /// background content genuinely fails to load, so a popup that waited only
    /// on that would leave a broken extension's toolbar button inert.
    func testReportsTimeoutWhenLoadingNeverReports() async throws {
        let warmUp = BrowserExtensionPopupBackgroundWarmUp(
            deadline: .milliseconds(50)
        ) { _ in }

        var outcomes: [BrowserExtensionPopupBackgroundWarmUp.Outcome] = []
        warmUp.prepare { outcomes.append($0) }
        XCTAssertTrue(outcomes.isEmpty)

        try await Task.sleep(for: .milliseconds(500))
        guard case .timedOut? = outcomes.first else {
            return XCTFail("The stalled background did not report a timeout.")
        }
    }

    func testReportsOnceWhenLoadingAndTheDeadlineBothArrive() async throws {
        var reportLoaded: (@MainActor (Error?) -> Void)?
        let warmUp = BrowserExtensionPopupBackgroundWarmUp(
            deadline: .milliseconds(50)
        ) { loaded in
            reportLoaded = loaded
        }

        var outcomes: [BrowserExtensionPopupBackgroundWarmUp.Outcome] = []
        warmUp.prepare { outcomes.append($0) }
        reportLoaded?(nil)
        try await Task.sleep(for: .milliseconds(500))
        reportLoaded?(nil)

        XCTAssertEqual(
            outcomes.count,
            1,
            "Background preparation finished more than once."
        )
    }

    func testReportsBackgroundLoadFailureWithoutCallingItLoaded() {
        struct FixtureError: Error {}

        let warmUp = BrowserExtensionPopupBackgroundWarmUp(
            deadline: .seconds(30)
        ) { completion in
            completion(FixtureError())
        }

        var outcome: BrowserExtensionPopupBackgroundWarmUp.Outcome?
        warmUp.prepare { outcome = $0 }

        guard case .failed(let error)? = outcome else {
            return XCTFail("The background load error was discarded.")
        }
        XCTAssertTrue(error is FixtureError)
    }

    /// An action can outlive the context it came from. Presenting immediately
    /// keeps that from swallowing the click.
    func testPresentsImmediatelyWithoutAContext() {
        let warmUp = BrowserExtensionPopupBackgroundWarmUp(
            context: nil,
            deadline: .seconds(30)
        )

        var outcomes: [BrowserExtensionPopupBackgroundWarmUp.Outcome] = []
        warmUp.prepare { outcomes.append($0) }

        guard case .loaded? = outcomes.first else {
            return XCTFail("A popup without background content was delayed.")
        }
    }
}

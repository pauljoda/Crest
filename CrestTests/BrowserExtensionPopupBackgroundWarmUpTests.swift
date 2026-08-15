import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionPopupBackgroundWarmUpTests: XCTestCase {
    func testPresentsAsSoonAsBackgroundContentReportsLoaded() {
        var reportLoaded: (@MainActor () -> Void)?
        let warmUp = BrowserExtensionPopupBackgroundWarmUp(
            deadline: .seconds(30)
        ) { loaded in
            reportLoaded = loaded
        }

        var presentations = 0
        warmUp.present { presentations += 1 }
        XCTAssertEqual(
            presentations,
            0,
            "The popup was presented before its background content loaded."
        )

        reportLoaded?()
        XCTAssertEqual(
            presentations,
            1,
            "The popup was not presented once its background content loaded."
        )
    }

    /// WebKit never calls `loadBackgroundContent`'s completion handler when
    /// background content genuinely fails to load, so a popup that waited only
    /// on that would leave a broken extension's toolbar button inert.
    func testPresentsAfterTheDeadlineWhenLoadingNeverReports() async throws {
        let warmUp = BrowserExtensionPopupBackgroundWarmUp(
            deadline: .milliseconds(50)
        ) { _ in }

        var presentations = 0
        warmUp.present { presentations += 1 }
        XCTAssertEqual(
            presentations,
            0,
            "The popup was presented before the deadline had passed."
        )

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(
            presentations,
            1,
            """
            The popup was never presented, so an extension whose background \
            content fails to load has an inert toolbar button.
            """
        )
    }

    func testPresentsOnceWhenLoadingAndTheDeadlineBothArrive() async throws {
        var reportLoaded: (@MainActor () -> Void)?
        let warmUp = BrowserExtensionPopupBackgroundWarmUp(
            deadline: .milliseconds(50)
        ) { loaded in
            reportLoaded = loaded
        }

        var presentations = 0
        warmUp.present { presentations += 1 }
        reportLoaded?()
        try await Task.sleep(for: .milliseconds(500))
        reportLoaded?()

        XCTAssertEqual(
            presentations,
            1,
            "The popup was presented more than once."
        )
    }

    /// An action can outlive the context it came from. Presenting immediately
    /// keeps that from swallowing the click.
    func testPresentsImmediatelyWithoutAContext() {
        let warmUp = BrowserExtensionPopupBackgroundWarmUp(
            context: nil,
            deadline: .seconds(30)
        )

        var presentations = 0
        warmUp.present { presentations += 1 }

        XCTAssertEqual(presentations, 1)
    }
}

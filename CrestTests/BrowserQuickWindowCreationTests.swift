import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserQuickWindowCreationTests: XCTestCase {
    // MARK: - Actions - Creation

    /// Protects command dispatch when the focused Quick Window has no page actions.
    func testNewQuickWindowFromAnEmptyQuickWindowKeepsItsSpaceAndDestination() async throws {
        try await checkCreation(startsEmpty: true)
    }

    /// Protects the focused page's Space and promotion destination when opening a sibling.
    func testNewQuickWindowFromALoadedQuickWindowKeepsItsSpaceAndDestination() async throws {
        try await checkCreation(startsEmpty: false)
    }

    /// Exercises shell dispatch with an unrelated locked browser Space, then
    /// verifies the child retains its source access gate and destination lifetime.
    private func checkCreation(startsEmpty: Bool) async throws {
        let host = WebKitShellHost()
        let application = try BrowserMacApplication()
        let shell = BrowserMacShell(engineHost: host)
        shell.start { application }
        let windows = try XCTUnwrap(shell.windows)
        let space = try XCTUnwrap(application.browser.shownSpace)
        application.browser.addSpace()
        let otherSpace = try XCTUnwrap(application.browser.shownSpace)
        XCTAssertNotEqual(space.id, otherSpace.id)

        // The destination's selected Space is unrelated to the Quick Window's.
        // Keeping it locked makes accidentally borrowing that selection fail.
        application.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: otherSpace.id)
        let destination = try XCTUnwrap(
            application.windowCoordinator.model(for: .normal(sourceWindowID: nil)))
        XCTAssertEqual(destination.browser.shownSpace?.id, otherSpace.id)
        application.pagePoolRegistry.register(destination.pages, browser: destination.browser, for: destination.id)
        defer {
            windows.closeQuickWindowsWithoutAsking()
            application.pagePoolRegistry.unregister(destination.pages, for: destination.id)
            application.windowCoordinator.closeWindow(destination.id)
        }

        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let request =
            startsEmpty
            ? BrowserQuickWindowRequest.empty(spaceAssignment: assignment, targetWindowID: destination.id)
            : BrowserQuickWindowRequest(
                url: try XCTUnwrap(URL(string: "about:blank")), spaceAssignment: assignment,
                targetWindowID: destination.id)
        let firstID = try XCTUnwrap(windows.openQuickWindow(request))
        let first = try XCTUnwrap(windows.quickWindow(firstID))
        first.makeKeyAndOrderFront(nil)
        try await waitUntil { NSApp.keyWindow === first }
        if startsEmpty {
            XCTAssertNil(windows.activeQuickWindowActions)
        } else {
            try await waitUntil { windows.activeQuickWindowActions != nil }
            XCTAssertEqual(windows.activeQuickWindowActions?.shownPageSpace?.id, space.id)
        }

        // This is the same dispatch used by File > New Quick Window and its shortcut.
        XCTAssertTrue(shell.canPerform(.newQuickWindow))
        shell.perform(.newQuickWindow)
        let second = try XCTUnwrap(NSApp.keyWindow)
        let secondID = try XCTUnwrap(second.identifier.flatMap { UUID(uuidString: $0.rawValue) })
        XCTAssertNotEqual(secondID, firstID)
        XCTAssertTrue(windows.quickWindow(secondID) === second)
        XCTAssertTrue(windows.quickWindow(firstID) === first)
        XCTAssertTrue(first.isVisible)
        XCTAssertTrue(second.isVisible)

        // Its inherited Space still gates new windows, independently of the
        // browser's selection, even though this empty window has no page.
        application.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: space.id)
        XCTAssertTrue(shell.canPerform(.newQuickWindow))
        shell.perform(.newQuickWindow)
        XCTAssertTrue(NSApp.keyWindow === second)
        application.browser.updateSpaceAccessPolicy(.open, in: space.id)

        // Once the destination is gone, the child cannot silently fall back
        // to the shared workspace when asked to create another Quick Window.
        application.pagePoolRegistry.unregister(destination.pages, for: destination.id)
        XCTAssertTrue(shell.canPerform(.newQuickWindow))
        shell.perform(.newQuickWindow)
        XCTAssertTrue(NSApp.keyWindow === second)
        XCTAssertTrue(windows.quickWindow(firstID) === first)
        XCTAssertTrue(windows.quickWindow(secondID) === second)
    }

    /// Yields for native focus or page preparation, failing after a bounded wait.
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for the Quick Window to become ready.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

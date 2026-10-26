import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserQuickWindowGeometryTests: XCTestCase {
    // MARK: - Actions - Persistence

    /// Protects shared geometry persistence across concurrent windows, older
    /// window closure, and a fresh reader of the same preferences suite.
    func testLatestAdjustedFrameReachesNewWindowsAndSurvivesReopeningPreferences() async throws {
        let suiteName = "BrowserQuickWindowGeometryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let visibleFrame = try XCTUnwrap(NSScreen.main).visibleFrame
        let first = try await makeWindow(defaults: defaults)
        defer { first.close() }
        let firstFrame = CGRect(
            x: visibleFrame.minX + 40, y: visibleFrame.minY + 50,
            width: visibleFrame.width * 0.55, height: visibleFrame.height * 0.55)
        first.setFrame(firstFrame, display: false)

        // A newly opened window takes the adjusted frame while its predecessor
        // is still open, so AppKit's exclusive autosave names cannot own it.
        let second = try await makeWindow(defaults: defaults)
        defer { second.close() }
        XCTAssertEqual(second.frame, first.frame)
        let latestFrame = CGRect(
            x: visibleFrame.minX + 70, y: visibleFrame.minY + 80,
            width: visibleFrame.width * 0.6, height: visibleFrame.height * 0.6)
        second.setFrame(latestFrame, display: false)
        first.close()

        // Closing an older window must not overwrite the most recent move or
        // resize, and a fresh preferences reader must recover both values.
        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let reopened = try await makeWindow(defaults: reopenedDefaults)
        defer { reopened.close() }
        XCTAssertEqual(reopened.frame, second.frame)
        XCTAssertNotEqual(reopened.frame, first.frame)
    }

    // MARK: - Actions - Windows

    /// Attaches the production geometry host to a native window and waits for
    /// deferred placement using the caller's disposable preferences suite.
    private func makeWindow(defaults: UserDefaults) async throws -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let geometry = BrowserQuickWindowGeometryHostView(
            pagePoolRegistry: nil, targetWindowID: nil, defaults: defaults)
        try XCTUnwrap(window.contentView).addSubview(geometry)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        geometry.updateWindowGeometry()
        return window
    }
}

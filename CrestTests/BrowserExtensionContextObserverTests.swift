import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionContextObserverTests: XCTestCase {
    func testStoppingObservationReleasesEveryContextNotification() async throws {
        let webExtension = try await WKWebExtension(
            resourceBaseURL: fixtureURL
        )
        let context = WKWebExtensionContext(for: webExtension)
        let observer = BrowserExtensionContextObserver()
        let permissionUpdate = expectation(
            description: "permission notification forwarded"
        )
        var permissionUpdateCount = 0
        var runtimeUpdateCount = 0
        observer.observe(
            context,
            permissionsDidChange: {
                permissionUpdateCount += 1
                permissionUpdate.fulfill()
            },
            runtimeSummaryDidChange: {
                runtimeUpdateCount += 1
            }
        )

        NotificationCenter.default.post(
            name: WKWebExtensionContext.permissionsWereGrantedNotification,
            object: context
        )
        await fulfillment(of: [permissionUpdate], timeout: 1)
        observer.stopObserving(context)

        NotificationCenter.default.post(
            name: WKWebExtensionContext.permissionsWereDeniedNotification,
            object: context
        )
        NotificationCenter.default.post(
            name: WKWebExtensionContext.errorsDidUpdateNotification,
            object: context
        )
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(permissionUpdateCount, 1)
        XCTAssertEqual(runtimeUpdateCount, 0)
    }

    func testReleasingObserverStopsEveryContextNotification() async throws {
        let webExtension = try await WKWebExtension(
            resourceBaseURL: fixtureURL
        )
        let context = WKWebExtensionContext(for: webExtension)
        var observer: BrowserExtensionContextObserver? =
            BrowserExtensionContextObserver()
        weak var releasedObserver = observer
        var permissionUpdateCount = 0
        observer?.observe(
            context,
            permissionsDidChange: {
                permissionUpdateCount += 1
            },
            runtimeSummaryDidChange: {}
        )

        observer = nil
        XCTAssertNil(releasedObserver)
        NotificationCenter.default.post(
            name: WKWebExtensionContext.permissionsWereGrantedNotification,
            object: context
        )
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(permissionUpdateCount, 0)
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(
                path: "Fixtures/SpaceProbeExtension",
                directoryHint: .isDirectory
            )
    }
}

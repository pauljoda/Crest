import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionSidebarWatchTests: XCTestCase {
    func testWatchDeliversOnlyItsClientsEventsAndCannotShareAnIdlePort() async throws {
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("watched"))
        let other = try XCTUnwrap(BrowserExtensionServiceClientID("other"))
        let store = BrowserExtensionSidebarStore(behaviorPersistence: InMemoryBrowserExtensionSidebarBehaviorStore())
        let space = SpaceID()
        let window = BrowserWindowID()
        for id in [client, other] {
            store.register(
                client: id, spaceID: space, defaults: .init(flavor: .sidePanel, path: "panel.html"),
                displayName: id.rawValue, baseURL: URL(string: "webkit-extension://\(id.rawValue)/")!)
        }
        let received = expectation(description: "Opened and closed")
        received.expectedFulfillmentCount = 2
        var kinds: [String] = []
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(grantedPermissions: ["sidePanel", "idle"], clientID: client),
            notificationService: nil, idleStateProvider: { _ in .active }, webpageMenuRegistry: .init(),
            sidebarService: store, sidebarEventMessage: { ["api": "sidebar.event", "kind": $0.kind.rawValue] },
            publish: {
                kinds.append($0["kind"] as! String)
                received.fulfill()
            }
        )
        defer { connection.stop() }
        try connection.receive(["api": "sidebar.watch"])
        XCTAssertThrowsError(try connection.receive(["api": "idle.watch", "detectionIntervalInSeconds": 60]))
        try store.open(for: client, in: window, tab: nil)
        try store.open(for: other, in: window, tab: nil)
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(kinds, ["opened", "closed"])
    }

    func testSidebarWatchRejectsAnUndeclaredCapability() throws {
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(grantedPermissions: [], clientID: BrowserExtensionServiceClientID("ungranted")),
            notificationService: nil, idleStateProvider: { _ in .active }, webpageMenuRegistry: .init(),
            publish: { _ in }
        )
        XCTAssertThrowsError(try connection.receive(["api": "sidebar.watch"]))
    }
}

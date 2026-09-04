import XCTest

@testable import Crest

/// The broker end of the emulated header table: the watch port that keeps
/// every context of one extension current, and the grant in front of it.
@MainActor
final class BrowserExtensionDeclarativeNetRequestWatchTests: XCTestCase {
    private let claude = BrowserExtensionServiceClientID("claude.space.personal")!

    private func rule(id: Int) -> BrowserExtensionEmulatedHeaderRule {
        BrowserExtensionEmulatedHeaderRule(
            id: id,
            condition: .init(urlFilter: "https://api.anthropic.com/*"),
            requestHeaders: [
                .init(header: "anthropic-client-platform", operation: .set, value: "ext")
            ]
        )
    }

    func testTheWatchPushesTheWholeTableAndCannotShareAPortWithAnotherWatch() async throws {
        let store = BrowserExtensionDeclarativeNetRequestStore(
            persistence: InMemoryBrowserExtensionDeclarativeNetRequestStore())
        let space = SpaceID()
        store.register(client: claude, spaceID: space)
        let received = expectation(description: "Session then dynamic")
        received.expectedFulfillmentCount = 2
        var messages: [[String: Any]] = []
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(
                grantedPermissions: ["declarativeNetRequestWithHostAccess", "idle"],
                clientID: claude),
            notificationService: nil, idleStateProvider: { _ in .active },
            webpageMenuRegistry: .init(),
            declarativeNetRequestService: store,
            declarativeNetRequestEventMessage: { rulesets in
                [
                    "api": "dnr.event",
                    "rulesets": [
                        "session": rulesets.session.map(\.payload),
                        "dynamic": rulesets.dynamic.map(\.payload),
                    ],
                ]
            },
            publish: {
                messages.append($0)
                received.fulfill()
            }
        )
        defer { connection.stop() }
        try connection.receive(["api": "dnr.watch"])
        // One port carries one watch.
        XCTAssertThrowsError(
            try connection.receive(["api": "idle.watch", "detectionIntervalInSeconds": 60]))

        store.setRules([rule(id: 1)], ruleset: .session, for: claude, in: space)
        store.setRules([rule(id: 2)], ruleset: .dynamic, for: claude, in: space)
        await fulfillment(of: [received], timeout: 2)

        XCTAssertEqual(messages.map { $0["api"] as? String }, ["dnr.event", "dnr.event"])
        let last = try XCTUnwrap(messages.last?["rulesets"] as? [String: Any])
        XCTAssertEqual((last["session"] as? [[String: Any]])?.map { $0["id"] as? Int }, [1])
        XCTAssertEqual((last["dynamic"] as? [[String: Any]])?.map { $0["id"] as? Int }, [2])
    }

    func testTheWatchIsRefusedWithoutADeclarativeNetRequestPermission() {
        let store = BrowserExtensionDeclarativeNetRequestStore(
            persistence: InMemoryBrowserExtensionDeclarativeNetRequestStore())
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(grantedPermissions: ["tabs"], clientID: claude),
            notificationService: nil, idleStateProvider: { _ in .active },
            webpageMenuRegistry: .init(),
            declarativeNetRequestService: store,
            publish: { _ in }
        )
        defer { connection.stop() }
        XCTAssertThrowsError(try connection.receive(["api": "dnr.watch"]))
    }
}

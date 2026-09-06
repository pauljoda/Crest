import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionBackgroundHealthTests: XCTestCase {
    func testBackgroundHealthWatchRequiresInternalBrokerAuthorization() throws {
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("health-test"))
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(clientID: client), notificationService: nil,
            idleStateProvider: { _ in .active }, webpageMenuRegistry: .init(), publish: { _ in }
        )
        XCTAssertThrowsError(try connection.receive(["api": "background.health.watch"]))
        XCTAssertThrowsError(try connection.receive(["api": "background.health.pong", "nonce": "unknown"]))
    }

    func testBackgroundHealthRequiresAResponseFromTheChallengedEndpoint() async throws {
        let health = BrowserExtensionBackgroundHealth()
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("health-test"))
        let endpoint = UUID()
        health.register(client: client, id: endpoint) { message in
            health.acknowledge(nonce: message["nonce"] as! String, endpoint: UUID())
        }
        let wrongEndpoint = await health.responds(client: client, timeout: .milliseconds(20))
        XCTAssertFalse(wrongEndpoint)
        health.register(client: client, id: endpoint) { message in
            health.acknowledge(nonce: message["nonce"] as! String, endpoint: endpoint)
        }
        let answered = await health.responds(client: client)
        XCTAssertTrue(answered)
    }

    func testBackgroundHealthRejectsDisconnectedEndpointWithoutWaiting() async throws {
        let health = BrowserExtensionBackgroundHealth()
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("health-test"))
        let endpoint = UUID()
        health.register(client: client, id: endpoint) { _ in
            health.unregister(client: client, id: endpoint)
        }
        let answered = await health.responds(client: client)
        XCTAssertFalse(answered)
    }

    func testOldDisconnectDoesNotRemoveReplacementBackground() async throws {
        let health = BrowserExtensionBackgroundHealth()
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("health-test"))
        let old = UUID()
        let replacement = UUID()
        health.register(client: client, id: old) { _ in }
        health.register(client: client, id: replacement) { message in
            health.acknowledge(nonce: message["nonce"] as! String, endpoint: replacement)
        }
        health.unregister(client: client, id: old)
        let answered = await health.responds(client: client)
        XCTAssertTrue(answered)
    }
}

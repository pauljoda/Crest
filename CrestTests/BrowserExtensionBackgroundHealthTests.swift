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
        var challengedNonce: String?
        health.register(client: client, id: old) { challengedNonce = $0["nonce"] as? String }
        let oldReply = Task { await health.responds(client: client) }
        while challengedNonce == nil { await Task.yield() }
        health.register(client: client, id: replacement) { message in
            health.acknowledge(nonce: message["nonce"] as! String, endpoint: replacement)
        }
        health.acknowledge(nonce: try XCTUnwrap(challengedNonce), endpoint: old)
        let oldAnswered = await oldReply.value
        XCTAssertFalse(oldAnswered, "A replaced endpoint must not satisfy the outstanding challenge.")
        health.unregister(client: client, id: old)
        XCTAssertEqual(health.endpointID(for: client), replacement)
        let answered = await health.responds(client: client)
        XCTAssertTrue(answered)
    }
}

import WebKit
import XCTest

@testable import Crest

/// The Swift half of the external-message relay: what a framed page is allowed
/// to send, how a delivery finds the extension's answer, and what the broker
/// accepts as that answer.
@MainActor
final class BrowserExtensionExternalMessageRelayTests: XCTestCase {
    private static let claudePatterns = ["https://claude.ai/*", "https://*.claude.ai/*"]

    // MARK: - Relay validation

    /// The page's own claim about which extension it may talk to is not
    /// evidence: a frame can reach the message handler without the alias
    /// script's own pattern check, so the relay repeats it in Swift.
    func testARelayedMessageRequiresTheNamedExtensionsOwnExternallyConnectablePattern() async throws {
        var delivered: [String] = []
        let relay = BrowserExtensionWebPageRuntimeRelay { _ in
            .init(
                externallyConnectableMatchPatterns: Self.claudePatterns,
                hasHostAccess: { _ in true },
                deliver: { json, _ in
                    delivered.append(String(decoding: json, as: UTF8.self))
                    return Data(#"{"ok":true}"#.utf8)
                })
        }
        let allowed = await relay.relayedResponse(
            extensionID: "fcoeoabgfenejglbffodgkkbkcdhcgfn",
            message: ["type": "ping"],
            frameURL: URL(string: "https://claude.ai/cic/new?surface=cic_sidepanel"),
            isMainFrame: false)
        XCTAssertEqual((allowed as? [String: Any])?["ok"] as? Bool, true)
        XCTAssertEqual(delivered, [#"{"type":"ping"}"#])

        let refused = await relay.relayedResponse(
            extensionID: "fcoeoabgfenejglbffodgkkbkcdhcgfn",
            message: ["type": "ping"],
            frameURL: URL(string: "https://elsewhere.test/"),
            isMainFrame: false)
        XCTAssertNil(refused, "A frame outside the pattern set is refused, silently.")
        XCTAssertEqual(delivered.count, 1)
    }

    /// The second half of WebKit's own web-page check. A pattern the extension
    /// wrote is not the same as access the person granted.
    func testARelayedMessageRequiresTheExtensionsHostAccess() async throws {
        let relay = BrowserExtensionWebPageRuntimeRelay { _ in
            .init(
                externallyConnectableMatchPatterns: Self.claudePatterns,
                hasHostAccess: { _ in false },
                deliver: { _, _ in
                    XCTFail("A message must not reach an extension without host access.")
                    return nil
                })
        }
        let response = await relay.relayedResponse(
            extensionID: "fcoeoabgfenejglbffodgkkbkcdhcgfn",
            message: ["type": "ping"],
            frameURL: URL(string: "https://claude.ai/"),
            isMainFrame: false)
        XCTAssertNil(response)
    }

    /// A refusal and an unanswered message are indistinguishable, so a page
    /// cannot use this channel to learn which extensions are installed.
    func testAnUnknownExtensionAndAFrameWithNoURLBothAnswerNothing() async throws {
        let relay = BrowserExtensionWebPageRuntimeRelay { extensionID in
            guard extensionID == "known" else { return nil }
            return .init(
                externallyConnectableMatchPatterns: ["<all_urls>"],
                hasHostAccess: { _ in true },
                deliver: { _, _ in Data("null".utf8) })
        }
        let unknown = await relay.relayedResponse(
            extensionID: "unknown", message: ["type": "ping"],
            frameURL: URL(string: "https://claude.ai/"), isMainFrame: false)
        XCTAssertNil(unknown)
        let noFrame = await relay.relayedResponse(
            extensionID: "known", message: ["type": "ping"], frameURL: nil, isMainFrame: false)
        XCTAssertNil(noFrame)
        let unencodable = await relay.relayedResponse(
            extensionID: "known", message: nil,
            frameURL: URL(string: "https://claude.ai/"), isMainFrame: false)
        XCTAssertNil(unencodable)
    }

    /// Chrome numbers a page's frames; WebKit publishes no frame identity to
    /// the app. The panel's own document is frame 0 and each framed URL takes
    /// the next number, stable for the life of the relay.
    func testTheSenderCarriesTheFramesURLOriginAndAStableFrameIdentifier() async throws {
        var senders: [BrowserExtensionExternalMessageDelivery.Sender] = []
        let relay = BrowserExtensionWebPageRuntimeRelay { _ in
            .init(
                externallyConnectableMatchPatterns: ["<all_urls>"],
                hasHostAccess: { _ in true },
                deliver: { _, sender in
                    senders.append(sender)
                    return nil
                })
        }
        let framed = URL(string: "https://claude.ai/cic/new?surface=cic_sidepanel")
        _ = await relay.relayedResponse(
            extensionID: "e", message: 1, frameURL: framed, isMainFrame: false)
        _ = await relay.relayedResponse(
            extensionID: "e", message: 1, frameURL: URL(string: "https://www.claude.ai/other"),
            isMainFrame: false)
        _ = await relay.relayedResponse(
            extensionID: "e", message: 1, frameURL: framed, isMainFrame: false)
        _ = await relay.relayedResponse(
            extensionID: "e", message: 1, frameURL: framed, isMainFrame: true)
        XCTAssertEqual(
            senders.map(\.url),
            [
                "https://claude.ai/cic/new?surface=cic_sidepanel",
                "https://www.claude.ai/other",
                "https://claude.ai/cic/new?surface=cic_sidepanel",
                "https://claude.ai/cic/new?surface=cic_sidepanel",
            ])
        XCTAssertEqual(
            senders.map(\.origin),
            ["https://claude.ai", "https://www.claude.ai", "https://claude.ai", "https://claude.ai"])
        XCTAssertEqual(senders.map(\.frameID), [1, 2, 1, 0])
    }

    /// A top-level scalar is a legal message and a legal answer, which
    /// `JSONSerialization` writes only with `.fragmentsAllowed`.
    func testScalarMessagesAndAnswersSurviveTheRoundTrip() async throws {
        var received: String?
        let relay = BrowserExtensionWebPageRuntimeRelay { _ in
            .init(
                externallyConnectableMatchPatterns: ["<all_urls>"],
                hasHostAccess: { _ in true },
                deliver: { json, _ in
                    received = String(decoding: json, as: UTF8.self)
                    return Data(#""pong""#.utf8)
                })
        }
        let response = await relay.relayedResponse(
            extensionID: "e", message: "ping", frameURL: URL(string: "https://claude.ai/"),
            isMainFrame: false)
        XCTAssertEqual(received, #""ping""#)
        XCTAssertEqual(response as? String, "pong")
    }

    // MARK: - Registry

    func testADeliveryFansOutToEveryPortAndCompletesOnTheFirstReply() async throws {
        let registry = BrowserExtensionExternalMessageRegistry(makeRequestID: { "req-1" })
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("probe"))
        XCTAssertFalse(registry.hasWatchers(for: client))
        let worker = registry.events(for: client)
        let panel = registry.events(for: client)
        XCTAssertTrue(registry.hasWatchers(for: client))

        async let response = registry.deliver(
            messageJSON: Data(#"{"type":"ping"}"#.utf8), sender: Self.sender, to: client)
        var workerIterator = worker.makeAsyncIterator()
        var panelIterator = panel.makeAsyncIterator()
        let toWorker = await workerIterator.next()
        let toPanel = await panelIterator.next()
        XCTAssertEqual(toWorker?.requestID, "req-1")
        XCTAssertEqual(toWorker, toPanel, "Every context of the extension hears the delivery.")
        XCTAssertEqual(toWorker?.sender.url, "https://claude.ai/cic/new")

        XCTAssertTrue(registry.resolve(requestID: "req-1", responseJSON: Data(#"{"ok":1}"#.utf8)))
        let answer = await response.map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(answer, #"{"ok":1}"#)
        XCTAssertFalse(
            registry.resolve(requestID: "req-1", responseJSON: Data("2".utf8)),
            "A second context answering after the first is dropped, as Chrome drops a late sendResponse.")
        XCTAssertFalse(registry.resolve(requestID: "unknown", responseJSON: nil))
    }

    /// Chrome ends a message nobody can receive with "Could not establish
    /// connection" rather than leaving the page waiting.
    func testAnExtensionWithNoListeningContextAnswersImmediately() async throws {
        let registry = BrowserExtensionExternalMessageRegistry()
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("silent"))
        let response = await registry.deliver(
            messageJSON: Data("1".utf8), sender: Self.sender, to: client)
        XCTAssertNil(response)
    }

    func testAnUnansweredDeliveryTimesOutRatherThanWaitingForever() async throws {
        let registry = BrowserExtensionExternalMessageRegistry(
            replyTimeout: .milliseconds(50), makeRequestID: { "req-slow" })
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("slow"))
        let events = registry.events(for: client)
        var iterator = events.makeAsyncIterator()
        async let response = registry.deliver(
            messageJSON: Data("1".utf8), sender: Self.sender, to: client)
        let delivery = await iterator.next()
        XCTAssertEqual(delivery?.requestID, "req-slow")
        let answered = await response
        XCTAssertNil(answered)
        XCTAssertFalse(
            registry.resolve(requestID: "req-slow", responseJSON: Data("1".utf8)),
            "A reply that arrives past the timeout names no live delivery.")
    }

    /// A context that unloads takes its listeners with it, so a delivery still
    /// waiting on them ends now rather than on the timeout.
    func testUnregisteringAContextEndsItsPendingDeliveries() async throws {
        let registry = BrowserExtensionExternalMessageRegistry(makeRequestID: { "req-gone" })
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("gone"))
        let events = registry.events(for: client)
        var iterator = events.makeAsyncIterator()
        async let response = registry.deliver(
            messageJSON: Data("1".utf8), sender: Self.sender, to: client)
        let delivery = await iterator.next()
        XCTAssertEqual(delivery?.requestID, "req-gone")
        registry.unregister(client: client)
        let ended = await response
        XCTAssertNil(ended)
        XCTAssertFalse(registry.hasWatchers(for: client))
    }

    // MARK: - Broker

    func testTheRuntimeWatchNeedsTheBrokerGrantAndItsOwnPortAndPublishesDeliveries() async throws {
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("watcher"))
        let registry = BrowserExtensionExternalMessageRegistry(makeRequestID: { "req-watch" })
        let coordinator = BrowserExtensionTabWindowCoordinator()

        let ungranted = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(clientID: client, allowsInternalCapabilityBroker: false),
            notificationService: nil, idleStateProvider: { _ in .active },
            webpageMenuRegistry: .init(), externalMessageService: registry, publish: { _ in })
        defer { ungranted.stop() }
        XCTAssertThrowsError(try ungranted.receive(["api": "runtime.watch"])) { error in
            XCTAssertEqual(
                error as? BrowserExtensionCapabilityBrokerError,
                .permissionDenied("internalCapabilityBroker"))
        }

        var published: [[String: Any]] = []
        let delivered = expectation(description: "delivery published")
        // No `chrome.*` permission is granted here on purpose: every extension
        // may hear from a website it named in its own externally_connectable.
        let granted = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(clientID: client, allowsInternalCapabilityBroker: true),
            notificationService: nil, idleStateProvider: { _ in .active },
            webpageMenuRegistry: .init(), externalMessageService: registry,
            externalMessageEventMessage: { coordinator.externalMessageEventMessage($0) },
            publish: { message in
                published.append(message)
                delivered.fulfill()
            })
        defer { granted.stop() }
        try granted.receive(["api": "runtime.watch"])
        // Re-subscribing on the same port is how the runtime recovers a
        // reconnect; sharing it with another capability is not.
        try granted.receive(["api": "runtime.watch"])
        XCTAssertThrowsError(
            try granted.receive(["api": "idle.watch", "detectionIntervalInSeconds": 60]))

        async let answered = registry.deliver(
            messageJSON: Data(#"{"type":"ping"}"#.utf8), sender: Self.sender, to: client)
        await fulfillment(of: [delivered], timeout: 5)
        XCTAssertEqual(published.first?["api"] as? String, "runtime.externalMessage")
        XCTAssertEqual(published.first?["requestId"] as? String, "req-watch")
        XCTAssertEqual(
            (published.first?["message"] as? [String: Any])?["type"] as? String, "ping")
        let sender = try XCTUnwrap(published.first?["sender"] as? [String: Any])
        XCTAssertEqual(sender["url"] as? String, "https://claude.ai/cic/new")
        XCTAssertEqual(sender["origin"] as? String, "https://claude.ai")
        XCTAssertEqual(sender["frameId"] as? Int, 1)
        XCTAssertNil(sender["tab"])
        XCTAssertNil(sender["id"])
        registry.resolve(requestID: "req-watch", responseJSON: nil)
        let unanswered = await answered
        XCTAssertNil(unanswered)
    }

    func testTheReplyIsAcceptedOnlyFromAVerifiedBrokerContextAndOnlyWellFormed() async throws {
        let webExtension = try await WKWebExtension(resourceBaseURL: fixtureURL)
        let context = WKWebExtensionContext(for: webExtension)
        let coordinator = BrowserExtensionTabWindowCoordinator()
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("reply"))
        let registry = coordinator.externalMessageRegistry

        // An unregistered context is refused outright.
        var unverified: (any Error)?
        XCTAssertTrue(
            coordinator.handleCapabilityBrokerExternalMessageReply(
                ["api": "runtime.externalMessageReply", "requestId": "x"],
                applicationIdentifier: BrowserExtensionNativeMessagingApplication
                    .capabilityBrokerIdentifier,
                extensionContext: context, replyHandler: { _, error in unverified = error }))
        XCTAssertNotNil(unverified)

        coordinator.registerCapabilityBrokerAuthorization(
            .init(clientID: client, allowsInternalCapabilityBroker: true), for: context)

        // Another host's message, and another api, both leave the funnel.
        XCTAssertFalse(
            coordinator.handleCapabilityBrokerExternalMessageReply(
                ["api": "runtime.externalMessageReply", "requestId": "x"],
                applicationIdentifier: "com.other.host", extensionContext: context,
                replyHandler: { _, _ in XCTFail("A foreign host must not be answered here.") }))
        XCTAssertFalse(
            coordinator.handleCapabilityBrokerExternalMessageReply(
                ["api": "runtime.watch"],
                applicationIdentifier: BrowserExtensionNativeMessagingApplication
                    .capabilityBrokerIdentifier,
                extensionContext: context,
                replyHandler: { _, _ in XCTFail("Another api must not be answered here.") }))

        var malformed: (any Error)?
        XCTAssertTrue(
            coordinator.handleCapabilityBrokerExternalMessageReply(
                ["api": "runtime.externalMessageReply"],
                applicationIdentifier: BrowserExtensionNativeMessagingApplication
                    .capabilityBrokerIdentifier,
                extensionContext: context, replyHandler: { _, error in malformed = error }))
        XCTAssertEqual(
            malformed as? BrowserExtensionCapabilityBrokerError, .invalidRequest)

        // A reply naming no live delivery is accepted and dropped, exactly as
        // Chrome drops a late `sendResponse`.
        var unmatched: Any?
        XCTAssertTrue(
            coordinator.handleCapabilityBrokerExternalMessageReply(
                ["api": "runtime.externalMessageReply", "requestId": "nobody"],
                applicationIdentifier: BrowserExtensionNativeMessagingApplication
                    .capabilityBrokerIdentifier,
                extensionContext: context, replyHandler: { value, _ in unmatched = value }))
        XCTAssertEqual((unmatched as? [String: Any])?["matched"] as? Bool, false)

        // A live delivery is completed with the value the listener sent, and an
        // omitted `response` is Chrome's unanswered message.
        let events = registry.events(for: client)
        var iterator = events.makeAsyncIterator()
        async let answered = registry.deliver(
            messageJSON: Data("1".utf8), sender: Self.sender, to: client)
        let delivery = await iterator.next()
        let requestID = try XCTUnwrap(delivery?.requestID)
        var matched: Any?
        XCTAssertTrue(
            coordinator.handleCapabilityBrokerExternalMessageReply(
                [
                    "api": "runtime.externalMessageReply", "requestId": requestID,
                    "response": ["ok": true],
                ],
                applicationIdentifier: BrowserExtensionNativeMessagingApplication
                    .capabilityBrokerIdentifier,
                extensionContext: context, replyHandler: { value, _ in matched = value }))
        XCTAssertEqual((matched as? [String: Any])?["matched"] as? Bool, true)
        let listenerAnswer = await answered.map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(listenerAnswer, #"{"ok":true}"#)
    }

    // MARK: - Fixtures

    private static let sender = BrowserExtensionExternalMessageDelivery.Sender(
        url: "https://claude.ai/cic/new", origin: "https://claude.ai", frameID: 1)

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/SidePanelProbeExtension", directoryHint: .isDirectory)
    }
}

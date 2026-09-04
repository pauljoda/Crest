import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionExternalMessagingCompatibilityScriptTests: XCTestCase {
    /// The whole point of the relay: a message WebKit refused to route reaches
    /// the extension's own `onMessageExternal` listener, and the answer that
    /// listener sends travels back as the one-shot reply the page is waiting
    /// on. Claude's side panel does exactly this — its framed app asks the
    /// worker for `get_sidepanel_host_info` and renders nothing until the
    /// answer arrives.
    func testARelayedDeliveryReachesTheListenerAndItsResponseComesBackAsTheReply() async throws {
        let result = try await evaluate(
            """
            const seen = [];
            addExternalMessageListener((message, sender, sendResponse) => {
                seen.push({message, sender: {...sender}, tab: sender.tab, id: sender.id});
                setTimeout(() => sendResponse({ok: true, echo: message.type}), 0);
                return true;
            });
            deliver({
                api: "runtime.externalMessage",
                requestId: "req-1",
                message: {type: "get_sidepanel_host_info"},
                sender: {url: "https://claude.ai/cic/new?surface=cic_sidepanel",
                    origin: "https://claude.ai", frameId: 1}
            });
            await settle();
            return {seen, requests};
            """)
        let seen = try XCTUnwrap(result["seen"] as? [[String: Any]])
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(
            (seen[0]["message"] as? [String: Any])?["type"] as? String,
            "get_sidepanel_host_info")
        let sender = try XCTUnwrap(seen[0]["sender"] as? [String: Any])
        XCTAssertEqual(
            sender["url"] as? String, "https://claude.ai/cic/new?surface=cic_sidepanel")
        XCTAssertEqual(sender["origin"] as? String, "https://claude.ai")
        XCTAssertEqual(sender["frameId"] as? Int, 1)
        XCTAssertEqual(
            Set(sender.keys), ["url", "origin", "frameId"],
            "Chrome's sender for a panel frame carries nothing else.")
        XCTAssertNil(seen[0]["tab"], "A side panel is not a tab, so Chrome leaves sender.tab undefined.")
        XCTAssertNil(seen[0]["id"], "The sender is a website, so there is no extension id.")
        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0]["api"] as? String, "runtime.externalMessageReply")
        XCTAssertEqual(requests[0]["requestId"] as? String, "req-1")
        let response = try XCTUnwrap(requests[0]["response"] as? [String: Any])
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["echo"] as? String, "get_sidepanel_host_info")
    }

    /// The three shapes Chrome accepts from a listener all have to answer, and
    /// they do because a relayed delivery runs through the same wrapper a
    /// native one does: the wrapper hands back a Promise whenever the listener
    /// claimed the message.
    func testAReturnedPromiseAndASynchronousSendResponseBothAnswer() async throws {
        let result = try await evaluate(
            """
            const promising = async () => ({from: "promise"});
            addExternalMessageListener(promising);
            deliver({api: "runtime.externalMessage", requestId: "req-promise", message: 1,
                sender: {url: "https://claude.ai/", origin: "https://claude.ai", frameId: 0}});
            await settle();
            removeExternalMessageListener(promising);
            addExternalMessageListener((message, sender, sendResponse) => {
                sendResponse("now");
            });
            deliver({api: "runtime.externalMessage", requestId: "req-sync", message: 2,
                sender: {url: "https://claude.ai/", origin: "https://claude.ai", frameId: 0}});
            await settle();
            return {requests};
            """)
        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0]["requestId"] as? String, "req-promise")
        XCTAssertEqual(
            (requests[0]["response"] as? [String: Any])?["from"] as? String, "promise")
        XCTAssertEqual(requests[1]["requestId"] as? String, "req-sync")
        XCTAssertEqual(requests[1]["response"] as? String, "now")
    }

    /// Chrome answers a page that reached a listener which claimed nothing
    /// with "the receiving end does not exist". Crest says the same thing by
    /// omitting `response`, which the page's alias turns into `lastError`.
    func testAnUnclaimedDeliveryRepliesWithNoResponse() async throws {
        let result = try await evaluate(
            """
            addExternalMessageListener(() => false);
            deliver({api: "runtime.externalMessage", requestId: "req-quiet", message: {type: "ping"},
                sender: {url: "https://claude.ai/", origin: "https://claude.ai", frameId: 0}});
            await settle();
            return {requests, hasResponseKey: requests.map(request => "response" in request)};
            """)
        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0]["requestId"] as? String, "req-quiet")
        XCTAssertEqual(result["hasResponseKey"] as? [Bool], [false])
    }

    /// Every context of the extension hears the delivery, and the first one to
    /// claim it owns the answer. A later listener's response is dropped rather
    /// than sent as a second reply.
    func testTheFirstClaimingListenerOwnsTheAnswer() async throws {
        let result = try await evaluate(
            """
            const seen = [];
            addExternalMessageListener((message) => { seen.push("first"); return undefined; });
            addExternalMessageListener(async () => { seen.push("second"); return "second"; });
            addExternalMessageListener(async () => { seen.push("third"); return "third"; });
            deliver({api: "runtime.externalMessage", requestId: "req-race", message: {},
                sender: {url: "https://claude.ai/", origin: "https://claude.ai", frameId: 0}});
            await settle();
            return {seen, requests};
            """)
        XCTAssertEqual(
            result["seen"] as? [String], ["first", "second", "third"],
            "Every listener still receives the message, as in Chrome.")
        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0]["response"] as? String, "second")
    }

    /// The watch is a live native port, so it exists only while somebody is
    /// listening. An extension with no `onMessageExternal` listener holds none.
    func testTheWatchConnectsWithTheFirstListenerAndDisconnectsWithTheLast() async throws {
        let result = try await evaluate(
            """
            const first = () => undefined;
            const second = () => undefined;
            const beforeAnyListener = [...watchEvents];
            addExternalMessageListener(first);
            addExternalMessageListener(second);
            const afterAdding = [...watchEvents];
            removeExternalMessageListener(first);
            const afterOneRemoval = [...watchEvents];
            removeExternalMessageListener(second);
            return {
                beforeAnyListener,
                afterAdding,
                afterOneRemoval,
                afterAll: [...watchEvents],
                subscription: externalMessageWatchSubscription()
            };
            """)
        XCTAssertEqual(result["beforeAnyListener"] as? [String], [])
        XCTAssertEqual(result["afterAdding"] as? [String], ["connect", "connect"])
        XCTAssertEqual(
            result["afterOneRemoval"] as? [String], ["connect", "connect"],
            "One remaining listener keeps the port open.")
        XCTAssertEqual(result["afterAll"] as? [String], ["connect", "connect", "disconnect"])
        XCTAssertEqual(
            result["subscription"] as? [String: String], ["api": "runtime.watch"])
    }

    /// The port carries whatever the broker publishes for this client. A
    /// message that is not a delivery, or one with no request to answer, must
    /// not produce a reply naming nothing.
    func testMalformedEnvelopesAreIgnored() async throws {
        let result = try await evaluate(
            """
            addExternalMessageListener(async () => "answered");
            deliver({api: "runtime.somethingElse", requestId: "req-x", message: {}});
            deliver({api: "runtime.externalMessage", message: {}});
            deliver({api: "runtime.externalMessage", requestId: 7, message: {}});
            deliver(undefined);
            await settle();
            return {requests};
            """)
        XCTAssertEqual((result["requests"] as? [Any])?.count, 0)
    }

    private func evaluate(_ body: String) async throws -> [String: Any] {
        let script = """
            const requests = [];
            const watchEvents = [];
            let subscription;
            let publishToWatch;
            const settle = async () => {
                for (let index = 0; index < 4; index += 1) {
                    await new Promise(resolve => setTimeout(resolve, 0));
                }
            };
            // Stands in for the runtime's own broker seam: records the
            // envelope and resolves, which is what a broker reply does.
            const requestCapability = (api, payload, args) => {
                requests.push({api, ...payload});
                return Promise.resolve({ok: true});
            };
            // Stands in for `capabilityWatch`, whose own reconnect behavior
            // has its own coverage. What matters here is when the fragment
            // opens and closes the port, what it subscribes with, and that a
            // published message reaches `onMessage`.
            const capabilityWatch = ({api, hasListeners, onMessage, subscription: subscribe}) => {
                subscription = subscribe;
                publishToWatch = onMessage;
                return Object.freeze({
                    connect() { watchEvents.push("connect"); },
                    disconnect() { watchEvents.push("disconnect"); },
                    resubscribe() { watchEvents.push("resubscribe"); }
                });
            };
            const externalMessageWatchSubscription = () => subscription();
            const deliver = (message) => publishToWatch(message);
            // The registry the generated runtime declares above the fragment.
            const externalMessageListeners = new Map();
            let externalMessageWatch;
            const registerExternalMessageListener = (listener, wrapper) => {
                externalMessageListeners.set(listener, wrapper);
                externalMessageWatch?.connect();
            };
            const unregisterExternalMessageListener = (listener) => {
                if (!externalMessageListeners.delete(listener)) return;
                if (externalMessageListeners.size > 0) return;
                externalMessageWatch?.disconnect();
            };
            // Mirrors `normalizeRuntimeMessageEvent`'s listener wrapper, which
            // is what the generated runtime registers here: a listener claims
            // the response by returning a Promise, by returning true and
            // answering later, or by answering synchronously, and the wrapper
            // expresses all three as a Promise.
            const wrapperFor = (listener) => (message, sender) => {
                let didRespond = false;
                let resolveResponse;
                const response = new Promise(resolve => { resolveResponse = resolve; });
                const sendResponse = (value) => { didRespond = true; resolveResponse(value); return true; };
                const result = listener(message, sender, sendResponse);
                if (result && typeof result.then === "function") return result;
                if (result === true || didRespond) return response;
                return result;
            };
            const addExternalMessageListener = (listener) =>
                registerExternalMessageListener(listener, wrapperFor(listener));
            const removeExternalMessageListener = (listener) =>
                unregisterExternalMessageListener(listener);
            \(BrowserExtensionExternalMessagingCompatibilityScript.source)
            return JSON.stringify(await (async () => { \(body) })());
            """
        let output = try await WKWebView().callAsyncJavaScript(
            script, arguments: [:], contentWorld: .page)
        let data = Data(try XCTUnwrap(output as? String).utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

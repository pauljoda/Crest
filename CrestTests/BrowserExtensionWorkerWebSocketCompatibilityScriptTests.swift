import WebKit
import XCTest

@testable import Crest

/// Pins the worker-side half of Crest's brokered WebSocket transport.
///
/// The fragment is evaluated in WebKit, against a fake capability port, so
/// what is checked is the JavaScript an extension actually runs rather than a
/// Swift restatement of it.
final class BrowserExtensionWorkerWebSocketCompatibilityScriptTests:
    XCTestCase
{
    @MainActor
    func testASocketReachesOpenAndRefusesToSendBeforeIt() async throws {
        let result = try await evaluate(
            """
            const port = makePort();
            const WebSocket = createBrokeredWebSocketClass(() => port);
            const socket = new WebSocket("wss://example.com/socket", ["codex"]);
            const opening = {
                readyState: socket.readyState,
                url: socket.url,
                protocol: socket.protocol,
                extensions: socket.extensions,
                binaryType: socket.binaryType,
                bufferedAmount: socket.bufferedAmount,
                tag: Object.prototype.toString.call(socket),
                name: WebSocket.name,
                constants: [
                    WebSocket.CONNECTING,
                    WebSocket.OPEN,
                    WebSocket.CLOSING,
                    WebSocket.CLOSED,
                    socket.CONNECTING,
                    socket.OPEN,
                    socket.CLOSING,
                    socket.CLOSED
                ]
            };
            let earlySend = "sent";
            try {
                socket.send("too early");
            } catch (error) {
                earlySend = error.name;
            }
            const events = [];
            socket.onopen = () => events.push("open");
            port.deliver({
                api: "websocket.event",
                kind: "open",
                protocol: "codex",
                extensions: "permessage-deflate"
            });
            socket.send("hello");
            const buffered = socket.bufferedAmount;
            await until(() => port.sent.length === 2);
            port.deliver({ api: "websocket.event", kind: "sent", bytes: 5 });
            return {
                opening,
                earlySend,
                events,
                openRequest: port.sent[0],
                sendRequest: port.sent[1],
                afterOpen: {
                    readyState: socket.readyState,
                    protocol: socket.protocol,
                    extensions: socket.extensions
                },
                buffered,
                bufferedAfterAcknowledgement: socket.bufferedAmount
            };
            """
        )

        let opening = try XCTUnwrap(result["opening"] as? [String: Any])
        XCTAssertEqual(opening["readyState"] as? Int, 0)
        XCTAssertEqual(opening["url"] as? String, "wss://example.com/socket")
        XCTAssertEqual(opening["protocol"] as? String, "")
        XCTAssertEqual(opening["binaryType"] as? String, "blob")
        XCTAssertEqual(opening["bufferedAmount"] as? Int, 0)
        XCTAssertEqual(opening["tag"] as? String, "[object WebSocket]")
        XCTAssertEqual(opening["name"] as? String, "WebSocket")
        XCTAssertEqual(
            opening["constants"] as? [Int],
            [0, 1, 2, 3, 0, 1, 2, 3]
        )

        XCTAssertEqual(result["earlySend"] as? String, "InvalidStateError")
        XCTAssertEqual(result["events"] as? [String], ["open"])

        let openRequest = try XCTUnwrap(result["openRequest"] as? [String: Any])
        XCTAssertEqual(openRequest["api"] as? String, "websocket.open")
        XCTAssertEqual(
            openRequest["url"] as? String,
            "wss://example.com/socket"
        )
        XCTAssertEqual(openRequest["protocols"] as? [String], ["codex"])

        let sendRequest = try XCTUnwrap(result["sendRequest"] as? [String: Any])
        XCTAssertEqual(sendRequest["api"] as? String, "websocket.send")
        XCTAssertEqual(sendRequest["text"] as? String, "hello")

        let afterOpen = try XCTUnwrap(result["afterOpen"] as? [String: Any])
        XCTAssertEqual(afterOpen["readyState"] as? Int, 1)
        XCTAssertEqual(afterOpen["protocol"] as? String, "codex")
        XCTAssertEqual(
            afterOpen["extensions"] as? String,
            "permessage-deflate"
        )

        XCTAssertEqual(result["buffered"] as? Int, 5)
        XCTAssertEqual(result["bufferedAfterAcknowledgement"] as? Int, 0)
    }

    @MainActor
    func testBinaryFramesCrossInBothDirectionsAsBase64() async throws {
        let result = try await evaluate(
            """
            const port = makePort();
            const WebSocket = createBrokeredWebSocketClass(() => port);
            const socket = new WebSocket("ws://127.0.0.1:1455/codex");
            port.deliver({ api: "websocket.event", kind: "open" });

            socket.send(new Uint8Array([0, 1, 254, 255]).buffer);
            socket.send(new Uint8Array([7, 8, 9]).subarray(1));
            socket.send(new Blob([new Uint8Array([64, 65])]));
            await until(() => port.sent.length === 4);

            const received = [];
            socket.onmessage = (event) => received.push(event);
            port.deliver({
                api: "websocket.event",
                kind: "message",
                binaryBase64: "AAH+/w=="
            });
            const asBlob = received[0];
            const blobBytes = Array.from(
                new Uint8Array(await asBlob.data.arrayBuffer())
            );
            socket.binaryType = "arraybuffer";
            socket.binaryType = "not-a-binary-type";
            port.deliver({
                api: "websocket.event",
                kind: "message",
                binaryBase64: "AAH+/w=="
            });
            port.deliver({
                api: "websocket.event",
                kind: "message",
                text: "plain"
            });
            const asBuffer = received[1];
            return {
                sent: port.sent.slice(1),
                binaryType: socket.binaryType,
                blobIsBlob: asBlob.data instanceof Blob,
                blobBytes,
                blobOrigin: asBlob.origin,
                bufferIsArrayBuffer: asBuffer.data instanceof ArrayBuffer,
                bufferBytes: Array.from(new Uint8Array(asBuffer.data)),
                textData: received[2].data
            };
            """
        )

        let sent = try XCTUnwrap(result["sent"] as? [[String: Any]])
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[0]["binaryBase64"] as? String, "AAH+/w==")
        XCTAssertEqual(sent[1]["binaryBase64"] as? String, "CAk=")
        XCTAssertEqual(sent[2]["binaryBase64"] as? String, "QEE=")
        XCTAssertEqual(result["binaryType"] as? String, "arraybuffer")
        XCTAssertEqual(result["blobIsBlob"] as? Bool, true)
        XCTAssertEqual(result["blobBytes"] as? [Int], [0, 1, 254, 255])
        XCTAssertEqual(result["blobOrigin"] as? String, "ws://127.0.0.1:1455")
        XCTAssertEqual(result["bufferIsArrayBuffer"] as? Bool, true)
        XCTAssertEqual(result["bufferBytes"] as? [Int], [0, 1, 254, 255])
        XCTAssertEqual(result["textData"] as? String, "plain")
    }

    /// The port going away is the transport's only way of saying the socket
    /// died, and the standard's answer to a failed connection is an `error`
    /// followed by a `close` carrying 1006.
    @MainActor
    func testALostPortFailsTheConnectionWith1006() async throws {
        let result = try await evaluate(
            """
            const port = makePort();
            const WebSocket = createBrokeredWebSocketClass(() => port);
            const socket = new WebSocket("wss://example.com/socket");
            const events = [];
            socket.onopen = () => events.push({ type: "open" });
            socket.onerror = () => events.push({ type: "error" });
            socket.onclose = (event) => events.push({
                type: "close",
                code: event.code,
                reason: event.reason,
                wasClean: event.wasClean,
                isCloseEvent: event instanceof CloseEvent
            });
            port.deliver({ api: "websocket.event", kind: "open" });
            socket.send("in flight");
            await until(() => port.sent.length === 2);
            port.dropped();
            const afterDrop = {
                readyState: socket.readyState,
                bufferedAmount: socket.bufferedAmount
            };
            socket.send("after close");
            await nextTick();
            return { events, afterDrop, sentCount: port.sent.length };
            """
        )

        let events = try XCTUnwrap(result["events"] as? [[String: Any]])
        XCTAssertEqual(
            events.map { $0["type"] as? String },
            ["open", "error", "close"]
        )
        XCTAssertEqual(events[2]["code"] as? Int, 1006)
        XCTAssertEqual(events[2]["reason"] as? String, "")
        XCTAssertEqual(events[2]["wasClean"] as? Bool, false)
        XCTAssertEqual(events[2]["isCloseEvent"] as? Bool, true)

        let afterDrop = try XCTUnwrap(result["afterDrop"] as? [String: Any])
        XCTAssertEqual(afterDrop["readyState"] as? Int, 3)
        XCTAssertEqual(afterDrop["bufferedAmount"] as? Int, 0)
        // The open request and the frame that was already on the wire — and
        // nothing at all from the send that came after the socket closed.
        XCTAssertEqual(result["sentCount"] as? Int, 2)
    }

    @MainActor
    func testAPeerCloseIsReportedWithItsCodeAndReason() async throws {
        let result = try await evaluate(
            """
            const port = makePort();
            const WebSocket = createBrokeredWebSocketClass(() => port);
            const socket = new WebSocket("wss://example.com/socket");
            const events = [];
            socket.onerror = () => events.push({ type: "error" });
            socket.onclose = (event) => events.push({
                type: "close",
                code: event.code,
                reason: event.reason,
                wasClean: event.wasClean
            });
            port.deliver({ api: "websocket.event", kind: "open" });
            socket.close(4001, "finished");
            const closing = socket.readyState;
            port.deliver({
                api: "websocket.event",
                kind: "close",
                code: 4001,
                reason: "finished",
                wasClean: true
            });
            return {
                events,
                closing,
                readyState: socket.readyState,
                closeRequest: port.sent[1],
                portDisconnected: port.disconnected
            };
            """
        )

        let events = try XCTUnwrap(result["events"] as? [[String: Any]])
        XCTAssertEqual(events.map { $0["type"] as? String }, ["close"])
        XCTAssertEqual(events[0]["code"] as? Int, 4001)
        XCTAssertEqual(events[0]["reason"] as? String, "finished")
        XCTAssertEqual(events[0]["wasClean"] as? Bool, true)
        XCTAssertEqual(result["closing"] as? Int, 2)
        XCTAssertEqual(result["readyState"] as? Int, 3)

        let closeRequest = try XCTUnwrap(
            result["closeRequest"] as? [String: Any]
        )
        XCTAssertEqual(closeRequest["api"] as? String, "websocket.close")
        XCTAssertEqual(closeRequest["code"] as? Int, 4001)
        XCTAssertEqual(closeRequest["reason"] as? String, "finished")
        XCTAssertEqual(result["portDisconnected"] as? Bool, true)
    }

    @MainActor
    func testTheConstructorAndCloseRejectWhatTheStandardRejects() async throws {
        let result = try await evaluate(
            """
            const port = makePort();
            const WebSocket = createBrokeredWebSocketClass(() => port);
            const named = (build) => {
                try {
                    build();
                    return "accepted";
                } catch (error) {
                    return error.name;
                }
            };
            const socket = new WebSocket("wss://example.com/socket");
            port.deliver({ api: "websocket.event", kind: "open" });
            return {
                httpURL: named(() => new WebSocket("https://example.com/")),
                fragment: named(
                    () => new WebSocket("wss://example.com/socket#frame")
                ),
                duplicateProtocol: named(
                    () => new WebSocket("wss://example.com/", ["a", "a"])
                ),
                blankProtocol: named(
                    () => new WebSocket("wss://example.com/", [""])
                ),
                closeCode: named(() => socket.close(1001)),
                applicationCode: named(() => socket.close(4999)),
                longReason: named(
                    () => socket.close(1000, "x".repeat(124))
                ),
                boundaryReason: named(
                    () => socket.close(1000, "x".repeat(123))
                )
            };
            """
        )

        XCTAssertEqual(result["httpURL"] as? String, "SyntaxError")
        XCTAssertEqual(result["fragment"] as? String, "SyntaxError")
        XCTAssertEqual(result["duplicateProtocol"] as? String, "SyntaxError")
        XCTAssertEqual(result["blankProtocol"] as? String, "SyntaxError")
        XCTAssertEqual(result["closeCode"] as? String, "InvalidAccessError")
        // The first accepted close moves the socket to CLOSING, so the rest
        // still have to validate before they become no-ops.
        XCTAssertEqual(result["applicationCode"] as? String, "accepted")
        XCTAssertEqual(result["longReason"] as? String, "SyntaxError")
        XCTAssertEqual(result["boundaryReason"] as? String, "accepted")
    }

    /// Without a transport the socket has to end the way a refused handshake
    /// does, which is what the facade this replaced did for every connection.
    @MainActor
    func testASocketWithoutATransportFailsAsynchronously() async throws {
        let result = try await evaluate(
            """
            const WebSocket = createBrokeredWebSocketClass(() => undefined);
            const socket = new WebSocket("wss://example.com/socket");
            const events = [];
            socket.onerror = () => events.push("error");
            socket.onclose = (event) => events.push(`close:${event.code}`);
            const immediate = socket.readyState;
            await nextTick();
            return { events, immediate, readyState: socket.readyState };
            """
        )

        XCTAssertEqual(result["immediate"] as? Int, 0)
        XCTAssertEqual(result["events"] as? [String], ["error", "close:1006"])
        XCTAssertEqual(result["readyState"] as? Int, 3)
    }

    /// The replacement is a worker-only workaround: a page context keeps
    /// WebKit's own implementation, and so does a worker on a build where the
    /// engine bug is absent.
    @MainActor
    func testTheGlobalIsReplacedOnlyInABackgroundWorkerThatNeedsIt()
        async throws
    {
        let probe = "return { replaced: globalThis.WebSocket !== nativeWebSocket };"
        for (fails, isWorker, expected) in [
            (true, true, true),
            (false, true, false),
            (true, false, false),
            (false, false, false),
        ] {
            let result = try await evaluate(
                probe,
                failsWorkerWebSockets: fails,
                isBackgroundWorker: isWorker
            )
            XCTAssertEqual(
                result["replaced"] as? Bool,
                expected,
                "failsWorkerWebSockets: \(fails), isBackgroundWorker: \(isWorker)"
            )
        }
    }

    @MainActor
    private func evaluate(
        _ body: String,
        failsWorkerWebSockets: Bool = false,
        isBackgroundWorker: Bool = false
    ) async throws -> [String: Any] {
        let webView = WKWebView()
        let value = try await webView.callAsyncJavaScript(
            Self.harness(
                body,
                failsWorkerWebSockets: failsWorkerWebSockets,
                isBackgroundWorker: isBackgroundWorker
            ),
            arguments: [:],
            contentWorld: .page
        )
        return try XCTUnwrap(value as? [String: Any])
    }

    /// Reproduces the scope the fragment is spliced into: it is a fragment of
    /// the generated compatibility runtime, not a program, and the four names
    /// below are what that runtime supplies.
    private static func harness(
        _ body: String,
        failsWorkerWebSockets: Bool,
        isBackgroundWorker: Bool
    ) -> String {
        """
        const nativeWebSocket = globalThis.WebSocket;
        const failsWorkerWebSockets = \(failsWorkerWebSockets);
        const isBackgroundWorker = \(isBackgroundWorker);
        const capabilityBrokerHost = "com.example.broker";
        const nativeRuntimeWithMethod = (methodName) => ({
            [methodName]: () => makePort()
        });
        const makePort = () => {
            const port = {
                sent: [],
                disconnected: false,
                messageListeners: [],
                disconnectListeners: [],
                postMessage: (message) => { port.sent.push(message); },
                disconnect: () => { port.disconnected = true; },
                onMessage: {
                    addListener: (listener) =>
                        port.messageListeners.push(listener)
                },
                onDisconnect: {
                    addListener: (listener) =>
                        port.disconnectListeners.push(listener)
                },
                deliver: (message) => {
                    for (const listener of port.messageListeners.slice()) {
                        listener(message);
                    }
                },
                dropped: () => {
                    for (const listener of port.disconnectListeners.slice()) {
                        listener();
                    }
                }
            };
            return port;
        };
        const nextTick = () => new Promise((resolve) => setTimeout(resolve, 0));
        const until = async (predicate) => {
            for (let attempt = 0; attempt < 200; attempt += 1) {
                if (predicate()) return true;
                await nextTick();
            }
            return false;
        };
        \(BrowserExtensionWorkerWebSocketCompatibilityScript.source)
        \(body)
        """
    }
}

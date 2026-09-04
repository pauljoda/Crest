import Foundation

/// The worker-side half of Crest's brokered WebSocket transport.
///
/// Spliced into the generated compatibility runtime at the point where a
/// background worker's `WebSocket` global is replaced. It is a fragment, not a
/// program: `failsWorkerWebSockets`, `isBackgroundWorker`,
/// `nativeRuntimeWithMethod`, and `capabilityBrokerHost` come from the runtime
/// it is spliced into.
///
/// It lives in its own file because it is long, self-contained, and worth
/// reading as JavaScript rather than as one more region of a seven-thousand
/// line string.
enum BrowserExtensionWorkerWebSocketCompatibilityScript {
    static let source = #"""
        // A background worker's WebSocket lives in the browser process.
        //
        // WebKit 27 hosts extension worker callbacks on the WebContent main
        // thread, and its worker-side WebSocket channel synchronously posts
        // bridge setup back to that same thread and then waits on a semaphore.
        // Constructing the native socket in a worker therefore deadlocks the
        // whole process, popups and extension pages sharing it included. The
        // native constructor is never reached from a worker: this class
        // presents the standard surface and carries every frame over one
        // native-messaging port, which Crest's capability broker turns into a
        // real socket outside the WebContent process. Page contexts keep
        // WebKit's own implementation.
        //
        // Binary frames cross as base64 because native-messaging payloads are
        // JSON. `bufferedAmount` is counted on this side: a send adds its byte
        // length and the broker's `sent` acknowledgement subtracts it again,
        // so the value is the bytes handed over and not yet confirmed on the
        // wire. Like the real property, it cannot see the socket's own kernel
        // buffer.
        const createBrokeredWebSocketClass = (openBrokerPort) => {
            const CONNECTING = 0;
            const OPEN = 1;
            const CLOSING = 2;
            const CLOSED = 3;
            const closeReasonByteLimit = 123;
            const encoder = new TextEncoder();
            const protocolTokenPattern = /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/;
            const toBase64 = (bytes) => {
                // `String.fromCharCode` is applied in chunks: a whole message
                // as one argument list overflows the call stack well before it
                // reaches a WebSocket's frame limit.
                const chunkSize = 0x8000;
                let binary = "";
                for (let index = 0; index < bytes.length; index += chunkSize) {
                    binary += String.fromCharCode.apply(
                        null,
                        bytes.subarray(index, index + chunkSize)
                    );
                }
                return btoa(binary);
            };
            const fromBase64 = (text) => {
                const binary = atob(text);
                const bytes = new Uint8Array(binary.length);
                for (let index = 0; index < binary.length; index += 1) {
                    bytes[index] = binary.charCodeAt(index);
                }
                return bytes;
            };

            class BrokeredWebSocket extends EventTarget {
                static CONNECTING = CONNECTING;
                static OPEN = OPEN;
                static CLOSING = CLOSING;
                static CLOSED = CLOSED;

                constructor(url, protocols) {
                    super();
                    const resolvedURL = new URL(
                        String(url),
                        globalThis.location?.href
                    );
                    if (
                        resolvedURL.protocol !== "ws:"
                        && resolvedURL.protocol !== "wss:"
                    ) {
                        throw new DOMException(
                            "WebSocket URL must use ws or wss.",
                            "SyntaxError"
                        );
                    }
                    if (resolvedURL.hash !== "") {
                        throw new DOMException(
                            "WebSocket URL must not have a fragment.",
                            "SyntaxError"
                        );
                    }
                    let requestedProtocols;
                    if (protocols === undefined || protocols === null) {
                        requestedProtocols = [];
                    } else if (typeof protocols === "string") {
                        requestedProtocols = [protocols];
                    } else {
                        requestedProtocols = Array.from(protocols, String);
                    }
                    const seenProtocols = new Set();
                    for (const value of requestedProtocols) {
                        if (
                            !protocolTokenPattern.test(value)
                            || seenProtocols.has(value)
                        ) {
                            throw new DOMException(
                                "WebSocket subprotocols must be unique tokens.",
                                "SyntaxError"
                            );
                        }
                        seenProtocols.add(value);
                    }
                    this._url = resolvedURL.href;
                    this._protocol = "";
                    this._extensions = "";
                    this._binaryType = "blob";
                    this._bufferedAmount = 0;
                    this._readyState = CONNECTING;
                    this._port = undefined;
                    this._sendQueue = Promise.resolve();
                    this.onopen = null;
                    this.onmessage = null;
                    this.onerror = null;
                    this.onclose = null;
                    this._connect(requestedProtocols);
                }

                get url() { return this._url; }
                get readyState() { return this._readyState; }
                get bufferedAmount() { return this._bufferedAmount; }
                get extensions() { return this._extensions; }
                get protocol() { return this._protocol; }
                get binaryType() { return this._binaryType; }
                set binaryType(value) {
                    if (value !== "blob" && value !== "arraybuffer") return;
                    this._binaryType = value;
                }

                send(data) {
                    if (this._readyState === CONNECTING) {
                        throw new DOMException(
                            "WebSocket is still connecting.",
                            "InvalidStateError"
                        );
                    }
                    if (this._readyState !== OPEN) return;
                    let bytes;
                    let frame;
                    if (typeof data === "string") {
                        bytes = encoder.encode(data).length;
                        frame = { text: data };
                    } else if (
                        typeof Blob === "function" && data instanceof Blob
                    ) {
                        // A Blob's bytes arrive asynchronously, so it becomes
                        // a promise and the queue below keeps it ahead of
                        // everything sent after it.
                        bytes = data.size;
                        frame = data.arrayBuffer().then((buffer) => ({
                            binaryBase64: toBase64(new Uint8Array(buffer))
                        }));
                    } else if (data instanceof ArrayBuffer) {
                        bytes = data.byteLength;
                        frame = {
                            binaryBase64: toBase64(new Uint8Array(data))
                        };
                    } else if (ArrayBuffer.isView(data)) {
                        bytes = data.byteLength;
                        frame = {
                            binaryBase64: toBase64(
                                new Uint8Array(
                                    data.buffer,
                                    data.byteOffset,
                                    data.byteLength
                                )
                            )
                        };
                    } else {
                        const text = String(data);
                        bytes = encoder.encode(text).length;
                        frame = { text };
                    }
                    this._bufferedAmount += bytes;
                    this._sendQueue = this._sendQueue
                        .then(() => Promise.resolve(frame))
                        .then((resolved) => this._post(resolved))
                        .catch(() => {});
                }

                close(code, reason) {
                    if (code !== undefined && code !== null) {
                        const numericCode = Number(code);
                        if (
                            numericCode !== 1000
                            && !(numericCode >= 3000 && numericCode <= 4999)
                        ) {
                            throw new DOMException(
                                "WebSocket close code is not allowed.",
                                "InvalidAccessError"
                            );
                        }
                    }
                    let closeReason;
                    if (reason !== undefined && reason !== null) {
                        closeReason = String(reason);
                        if (
                            encoder.encode(closeReason).length
                                > closeReasonByteLimit
                        ) {
                            throw new DOMException(
                                "WebSocket close reason is too long.",
                                "SyntaxError"
                            );
                        }
                    }
                    if (
                        this._readyState === CLOSING
                        || this._readyState === CLOSED
                    ) {
                        return;
                    }
                    this._readyState = CLOSING;
                    const request = { api: "websocket.close" };
                    if (code !== undefined && code !== null) {
                        request.code = Number(code);
                    }
                    if (closeReason !== undefined) {
                        request.reason = closeReason;
                    }
                    if (!this._port) {
                        globalThis.setTimeout(
                            () => this._failConnection(),
                            0
                        );
                        return;
                    }
                    try {
                        this._port.postMessage(request);
                    } catch {
                        this._failConnection();
                    }
                }

                _connect(protocols) {
                    let port;
                    try {
                        port = openBrokerPort();
                    } catch {
                        port = undefined;
                    }
                    if (!port) {
                        // No transport at all. Report the same asynchronous
                        // network failure a refused handshake produces, which
                        // is the outcome clients already retry against.
                        globalThis.setTimeout(
                            () => this._failConnection(),
                            0
                        );
                        return;
                    }
                    this._port = port;
                    try {
                        port.onMessage?.addListener(
                            (message) => this._receive(message)
                        );
                        port.onDisconnect?.addListener(() => {
                            this._port = undefined;
                            this._failConnection();
                        });
                        port.postMessage({
                            api: "websocket.open",
                            url: this._url,
                            protocols
                        });
                    } catch {
                        this._port = undefined;
                        globalThis.setTimeout(
                            () => this._failConnection(),
                            0
                        );
                    }
                }

                _receive(message) {
                    if (!message || message.api !== "websocket.event") return;
                    switch (message.kind) {
                    case "open":
                        if (this._readyState !== CONNECTING) return;
                        this._readyState = OPEN;
                        this._protocol =
                            typeof message.protocol === "string"
                                ? message.protocol
                                : "";
                        this._extensions =
                            typeof message.extensions === "string"
                                ? message.extensions
                                : "";
                        this._dispatch(new Event("open"));
                        return;
                    case "message":
                        this._receiveMessage(message);
                        return;
                    case "sent":
                        this._bufferedAmount = Math.max(
                            0,
                            this._bufferedAmount - (Number(message.bytes) || 0)
                        );
                        return;
                    case "error":
                        this._dispatch(new Event("error"));
                        return;
                    case "close":
                        this._reportClose(
                            message.code,
                            message.reason,
                            message.wasClean
                        );
                        return;
                    default:
                        return;
                    }
                }

                _receiveMessage(message) {
                    if (this._readyState !== OPEN) return;
                    let data;
                    if (typeof message.text === "string") {
                        data = message.text;
                    } else if (typeof message.binaryBase64 === "string") {
                        const bytes = fromBase64(message.binaryBase64);
                        data = this._binaryType === "arraybuffer"
                            ? bytes.buffer
                            : new Blob([bytes]);
                    } else {
                        return;
                    }
                    this._dispatch(new MessageEvent("message", {
                        data,
                        origin: this._origin()
                    }));
                }

                _post(frame) {
                    if (this._readyState !== OPEN || !this._port) return;
                    try {
                        this._port.postMessage(
                            Object.assign({ api: "websocket.send" }, frame)
                        );
                    } catch {
                        this._failConnection();
                    }
                }

                _failConnection() {
                    if (this._readyState === CLOSED) return;
                    // "Fail the WebSocket connection" fires `error` and then a
                    // `close` carrying 1006, the code no close frame can hold.
                    this._dispatch(new Event("error"));
                    this._reportClose(1006, "", false);
                }

                _reportClose(code, reason, wasClean) {
                    if (this._readyState === CLOSED) return;
                    this._readyState = CLOSED;
                    this._bufferedAmount = 0;
                    const port = this._port;
                    this._port = undefined;
                    try { port?.disconnect(); } catch {}
                    const numericCode = Number(code);
                    this._dispatch(this._closeEvent(
                        Number.isFinite(numericCode) ? numericCode : 1006,
                        typeof reason === "string" ? reason : "",
                        wasClean === true
                    ));
                }

                _closeEvent(code, reason, wasClean) {
                    try {
                        return new CloseEvent("close", {
                            code,
                            reason,
                            wasClean
                        });
                    } catch {
                        const event = new Event("close");
                        Object.defineProperties(event, {
                            code: { value: code, enumerable: true },
                            reason: { value: reason, enumerable: true },
                            wasClean: { value: wasClean, enumerable: true }
                        });
                        return event;
                    }
                }

                _origin() {
                    try {
                        return new URL(this._url).origin;
                    } catch {
                        return "";
                    }
                }

                _dispatch(event) {
                    super.dispatchEvent(event);
                    const handler = this[`on${event.type}`];
                    if (typeof handler === "function") {
                        try { handler.call(this, event); } catch {}
                    }
                }
            }

            for (const [name, value] of Object.entries({
                CONNECTING,
                OPEN,
                CLOSING,
                CLOSED
            })) {
                Object.defineProperty(
                    BrokeredWebSocket.prototype,
                    name,
                    { value, enumerable: true }
                );
            }
            Object.defineProperty(
                BrokeredWebSocket.prototype,
                Symbol.toStringTag,
                { value: "WebSocket" }
            );
            // Extension code feature-detects on the constructor's name as
            // often as on the global's presence, and what it is looking at is
            // a WebSocket.
            try {
                Object.defineProperty(
                    BrokeredWebSocket,
                    "name",
                    { value: "WebSocket", configurable: true }
                );
            } catch {}
            return BrokeredWebSocket;
        };

        const installBrokeredWorkerWebSocket = () => {
            if (!failsWorkerWebSockets || !isBackgroundWorker) {
                return;
            }
            const BrokeredWebSocket = createBrokeredWebSocketClass(() => {
                // Resolve the transport per socket, as every other brokered
                // capability does: WebKit can replace the runtime facade after
                // this script starts.
                const runtime = nativeRuntimeWithMethod("connectNative");
                const connectNative = runtime?.connectNative;
                if (typeof connectNative !== "function") return undefined;
                return Reflect.apply(
                    connectNative,
                    runtime,
                    [capabilityBrokerHost]
                );
            });
            try {
                Object.defineProperty(globalThis, "WebSocket", {
                    value: BrokeredWebSocket,
                    configurable: true,
                    writable: true
                });
            } catch {}
        };
        installBrokeredWorkerWebSocket();
        """#
}

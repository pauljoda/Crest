import Foundation

/// One WebSocket a background worker asked Crest to open on its behalf.
///
/// WebKit 27 cannot run a WebSocket inside an extension's background worker:
/// its worker-side channel posts bridge setup to the WebContent main thread
/// and waits on it, so constructing the native socket deadlocks the whole
/// process. The socket therefore lives here, in the browser process, and the
/// worker drives it over the native-messaging port it is already allowed to
/// open. One port carries one socket, so the port's lifetime is the socket's:
/// when the worker drops the port — or the extension unloads — the connection
/// goes with it.
///
/// The payloads are JSON, which has no binary type, so binary frames cross the
/// boundary base64-encoded in `binaryBase64`.
@MainActor
final class BrowserExtensionBrokeredWebSocket {
    private enum State {
        case idle
        case connecting
        case open
        case closing
        case closed
    }

    private let policy: BrowserExtensionWebSocketPolicy
    private let origin: String?
    private let publish: ([String: Any]) -> Void
    private var state: State = .idle
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var sessionDelegate: SessionDelegate?
    private var requestedCloseCode = 1000
    private var requestedCloseReason = ""
    private var closedBeforeOpen = false
    private var didReportClose = false

    init(
        policy: BrowserExtensionWebSocketPolicy,
        origin: String?,
        publish: @escaping ([String: Any]) -> Void
    ) {
        self.policy = policy
        self.origin = origin
        self.publish = publish
    }

    /// Opens the connection the worker described.
    ///
    /// A refusal throws rather than reporting a socket-level error: the broker
    /// answers a rejected request by dropping the port, and the worker-side
    /// facade turns that disconnect into the `error` and `close` pair a failed
    /// WebSocket handshake produces in any browser.
    func open(_ request: [String: Any]) throws {
        guard state == .idle else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        guard
            let rawURL = request["url"] as? String,
            let url = URL(string: rawURL),
            let scheme = url.scheme?.lowercased(),
            scheme == "ws" || scheme == "wss"
        else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        guard policy.allowsConnection(to: url) else {
            throw BrowserExtensionCapabilityBrokerError.permissionDenied(
                "connect-src"
            )
        }
        let declaredProtocols = request["protocols"] as? [String] ?? []
        let protocols = declaredProtocols.filter { !$0.isEmpty }

        var urlRequest = URLRequest(url: url)
        // Chrome sends the extension's own origin, and a local app server that
        // allow-lists its companion extension checks exactly that. WebKit's
        // per-Space extension origin would not be recognized by any of them.
        if let origin {
            urlRequest.setValue(origin, forHTTPHeaderField: "Origin")
        }
        if !protocols.isEmpty {
            urlRequest.setValue(
                protocols.joined(separator: ", "),
                forHTTPHeaderField: "Sec-WebSocket-Protocol"
            )
        }

        // An extension socket carries the extension's own credentials in its
        // payload, never the browser's: no cookie jar, no credential store,
        // no cache.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        let delegate = SessionDelegate()
        delegate.owner = self
        sessionDelegate = delegate
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: .main
        )
        self.session = session
        let task = session.webSocketTask(with: urlRequest)
        self.task = task
        state = .connecting
        task.resume()
        receiveNextMessage()
    }

    func send(_ request: [String: Any]) throws {
        if let text = request["text"] as? String {
            send(.string(text), bytes: text.utf8.count)
            return
        }
        guard
            let base64 = request["binaryBase64"] as? String,
            let data = Data(base64Encoded: base64)
        else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        send(.data(data), bytes: data.count)
    }

    /// Starts the closing handshake.
    ///
    /// Code and reason are already validated by the worker-side facade, which
    /// raises the spec's `InvalidAccessError` and `SyntaxError` before any of
    /// this is reached.
    func close(_ request: [String: Any]) {
        guard state == .connecting || state == .open else { return }
        if let code = request["code"] as? NSNumber {
            requestedCloseCode = code.intValue
        }
        requestedCloseReason = request["reason"] as? String ?? ""
        // Closing a socket that never opened fails the connection rather than
        // completing a handshake that never started, so the page sees 1006.
        closedBeforeOpen = state == .connecting
        state = .closing
        task?.cancel(
            with: URLSessionWebSocketTask.CloseCode(
                rawValue: requestedCloseCode
            ) ?? .normalClosure,
            reason: Data(requestedCloseReason.utf8)
        )
    }

    /// Tears the socket down without reporting anything: the port that would
    /// have carried the report is already gone.
    func stop() {
        didReportClose = true
        state = .closed
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        sessionDelegate?.owner = nil
        sessionDelegate = nil
    }

    private func send(
        _ message: URLSessionWebSocketTask.Message,
        bytes: Int
    ) {
        guard state == .open, let task else { return }
        task.send(message) { [weak self] error in
            Task { @MainActor in
                // A failed send means the connection is already going down,
                // and the task's completion reports that. Acknowledging only
                // a real send keeps `bufferedAmount` from being credited for
                // bytes that never left; the close that follows resets it.
                guard let self, error == nil else { return }
                self.publishEvent(["kind": "sent", "bytes": bytes])
            }
        }
    }

    private func receiveNextMessage() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                self?.receive(result)
            }
        }
    }

    private func receive(
        _ result: Result<URLSessionWebSocketTask.Message, any Error>
    ) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                publishEvent(["kind": "message", "text": text])
            case .data(let data):
                publishEvent([
                    "kind": "message",
                    "binaryBase64": data.base64EncodedString(),
                ])
            @unknown default:
                break
            }
            receiveNextMessage()
        case .failure:
            // The receive loop ends for a clean close and a broken connection
            // alike, and the error it reports cannot tell them apart. Say
            // nothing: `didCompleteWithError` is the task's last delegate
            // message and arrives after any close frame, so it is the one
            // place that knows which happened.
            break
        }
    }

    private func failConnection() {
        guard !didReportClose else { return }
        publishEvent(["kind": "error"])
        reportClose(code: 1006, reason: "", wasClean: false)
    }

    private func reportClose(code: Int, reason: String, wasClean: Bool) {
        guard !didReportClose else { return }
        didReportClose = true
        state = .closed
        publishEvent([
            "kind": "close",
            "code": code,
            "reason": reason,
            "wasClean": wasClean,
        ])
        task = nil
        session?.invalidateAndCancel()
        session = nil
        sessionDelegate?.owner = nil
        sessionDelegate = nil
    }

    private func publishEvent(_ event: [String: Any]) {
        var message = event
        message["api"] = "websocket.event"
        publish(message)
    }

    private func didOpen(negotiatedProtocol: String?, extensions: String) {
        guard state == .connecting else { return }
        state = .open
        publishEvent([
            "kind": "open",
            "protocol": negotiatedProtocol ?? "",
            "extensions": extensions,
        ])
    }

    private func didReceiveCloseFrame(code: Int, reason: String) {
        // `CloseCode.invalid` is a close frame that carried no code at all,
        // which the WebSocket API reports to the page as 1005.
        reportClose(
            code: code == 0 ? 1005 : code,
            reason: reason,
            wasClean: true
        )
    }

    private func didComplete(withError error: (any Error)?) {
        guard !didReportClose else { return }
        // A close this side started is reported clean: the closing frame went
        // out, and whether the peer echoed it before dropping the socket is
        // not something `URLSession` distinguishes here.
        if state == .closing, !closedBeforeOpen {
            reportClose(
                code: requestedCloseCode,
                reason: requestedCloseReason,
                wasClean: true
            )
            return
        }
        _ = error
        failConnection()
    }

    @MainActor
    private final class SessionDelegate:
        NSObject,
        URLSessionWebSocketDelegate
    {
        weak var owner: BrowserExtensionBrokeredWebSocket?

        nonisolated func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didOpenWithProtocol negotiatedProtocol: String?
        ) {
            let response = webSocketTask.response as? HTTPURLResponse
            let extensions =
                response?.value(
                    forHTTPHeaderField: "Sec-WebSocket-Extensions"
                ) ?? ""
            MainActor.assumeIsolated {
                owner?.didOpen(
                    negotiatedProtocol: negotiatedProtocol,
                    extensions: extensions
                )
            }
        }

        nonisolated func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            let text = reason.flatMap { String(data: $0, encoding: .utf8) }
            MainActor.assumeIsolated {
                owner?.didReceiveCloseFrame(
                    code: closeCode.rawValue,
                    reason: text ?? ""
                )
            }
        }

        nonisolated func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: (any Error)?
        ) {
            MainActor.assumeIsolated {
                owner?.didComplete(withError: error)
            }
        }
    }
}

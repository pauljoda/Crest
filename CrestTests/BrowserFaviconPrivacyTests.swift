import Foundation
import Network
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserFaviconPrivacyTests: XCTestCase {
    private var navigations: [FaviconPrivacyNavigation] = []

    func testCapturePreservesCookieScopeAndSpaceIsolationAcrossResourceRedirects() async throws {
        let server = try FaviconPrivacyServer()
        try await server.start()
        defer { server.stop() }
        let pageURL = server.url(host: "parent.localhost", path: "/private/page?secret=query#fragment")
        let webView = makeWebView()
        try await load(server.url(host: "other.localhost", path: "/same-site-cookies"), in: webView)
        try await load(pageURL, in: webView)
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.contains { $0.name == "hostOnly" })
        XCTAssertTrue(cookies.contains { $0.name == "domainCookie" })
        XCTAssertTrue(cookies.contains { $0.name == "strictOther" })
        XCTAssertTrue(cookies.contains { $0.name == "laxOther" })
        attach(
            cookies.map {
                "\($0.name): domain=\($0.domain), path=\($0.path), secure=\($0.isSecure), properties=\($0.properties ?? [:])"
            }.joined(separator: "\n"), name: "WebKit cookie representation")

        // A second Space has a distinct store even while both pages are alive.
        let otherSpace = makeWebView()
        try await load(server.url(host: "parent.localhost", path: "/other-space"), in: otherSpace)
        try await webView.evaluateJavaScript(
            """
            document.head.innerHTML = '<link rel="manifest" href="/private/manifest-redirect">';
            """)
        let data = await BrowserFaviconCapture.capture(from: webView)
        XCTAssertNotNil(data, "An authenticated manifest and icon must remain discoverable")

        let requests = server.requests.filter {
            ($0.path.contains("manifest") || $0.path.contains("icon")) && $0.headers["sec-fetch-dest"] != "manifest"
        }
        attach(requests.map(\.description).joined(separator: "\n"), name: "Resource wire requests")
        for path in [
            "/private/manifest-redirect", "/private/manifest.json", "/child-icon", "/private/cross-site-icon-redirect",
            "/same-site-icon", "/privateer/icon", "/private/icon-redirect", "/public/icon",
        ] {
            XCTAssertTrue(requests.contains { $0.path == path }, "Missing wire capture for \(path)")
        }
        for request in requests {
            let cookie = request.headers["cookie", default: ""]
            XCTAssertNil(request.headers["referer"], request.description)
            XCTAssertFalse(cookie.contains("spaceB="), request.description)
            XCTAssertFalse(cookie.contains("strictOther="), request.description)
            XCTAssertFalse(cookie.contains("laxOther="), request.description)
            // WebKit permits Secure cookies on trustworthy localhost HTTP.
            // Native fallback requests must never carry them.
            if request.headers["sec-fetch-mode"] == nil {
                XCTAssertFalse(cookie.contains("secureOnly="), request.description)
            }
            if request.host.hasPrefix("child.") {
                XCTAssertFalse(cookie.contains("hostOnly="), request.description)
            }
            if !request.path.hasPrefix("/private/") {
                XCTAssertFalse(cookie.contains("privatePath="), request.description)
            }
        }
        let authenticated = requests.filter { $0.path == "/private/manifest.json" || $0.path == "/public/icon" }
        XCTAssertEqual(authenticated.count, 2)
        XCTAssertTrue(authenticated.allSatisfy { $0.headers["cookie", default: ""].contains("hostOnly=spaceA") })
        withExtendedLifetime(otherSpace) {}
    }

    func testCaptureOmitsReferrersForDocumentAndElementPolicies() async throws {
        let server = try FaviconPrivacyServer()
        try await server.start()
        defer { server.stop() }
        for policy in ["no-referrer", "origin"] {
            let webView = makeWebView()
            try await load(
                server.url(host: "parent.localhost", path: "/policy/\(policy)?secret=query#fragment"), in: webView)
            try await webView.evaluateJavaScript(
                """
                document.head.innerHTML += '<link rel="manifest" href="http://child.parent.localhost:\(server.port)/policy-manifest-redirect"><link rel="icon" referrerpolicy="\(policy)" href="http://child.parent.localhost:\(server.port)/policy-icon-redirect?case=\(policy)">';
                """)
            let data = await BrowserFaviconCapture.capture(from: webView)
            XCTAssertNotNil(data, "Public cross-origin icons without CORS must still load")
        }
        let requests = server.requests.filter {
            ($0.path.hasPrefix("/policy-icon") || $0.path.hasPrefix("/policy-manifest"))
                && $0.headers["sec-fetch-dest"] != "manifest"
        }
        attach(requests.map(\.description).joined(separator: "\n"), name: "Policy wire requests")
        for path in [
            "/policy-manifest-redirect", "/policy-manifest.json", "/policy-manifest-icon-redirect",
            "/policy-manifest-icon", "/policy-icon-redirect", "/policy-icon",
        ] {
            XCTAssertGreaterThanOrEqual(requests.filter { $0.path == path }.count, 2)
        }
        for request in requests {
            XCTAssertNil(request.headers["referer"], request.description)
            XCTAssertNil(request.headers["authorization"], request.description)
        }
    }

    func testSecurePageCaptureDoesNotDiscloseReferrersOrCookiesOnDowngrade() async throws {
        let server = try FaviconPrivacyServer()
        try await server.start()
        defer { server.stop() }
        let secureServer = try FaviconPrivacyServer(tls: true)
        try await secureServer.start()
        defer { secureServer.stop() }
        let webView = makeWebView()
        try await load(
            secureServer.url(host: "parent.localhost", path: "/private/page?secret=query#fragment"), in: webView)
        try await webView.evaluateJavaScript(
            """
            document.head.innerHTML = '<link rel="icon" href="/downgrade-icon?port=\(server.port)">';
            """)
        // WebKit can block the insecure redirect as mixed content. It must not
        // disclose headers even when there is no usable image at the end.
        _ = await BrowserFaviconCapture.capture(from: webView)
        let secureRequests = secureServer.requests.filter { $0.path == "/downgrade-icon" }
        XCTAssertFalse(secureRequests.isEmpty)
        XCTAssertTrue(secureRequests.contains { $0.headers["cookie", default: ""].contains("secureOnly=secure") })
        try await webView.evaluateJavaScript(
            """
            document.head.innerHTML = '<link rel="icon" href="http://child.parent.localhost:\(server.port)/policy-icon-redirect">';
            """)
        let publicData = await BrowserFaviconCapture.capture(from: webView)
        XCTAssertNotNil(publicData)
        let downgraded = server.requests.filter { $0.path == "/cors-icon" || $0.path.hasPrefix("/policy-icon") }
        XCTAssertTrue(downgraded.contains { $0.path == "/policy-icon" })
        attach(
            (secureRequests + downgraded).map(\.description).joined(separator: "\n"),
            name: "HTTPS downgrade wire requests")
        for request in secureRequests + downgraded {
            XCTAssertNil(request.headers["referer"], request.description)
        }
        for request in downgraded {
            XCTAssertNil(request.headers["cookie"], request.description)
            XCTAssertNil(request.headers["authorization"], request.description)
        }
    }

    func testNativeFallbackOmitsURLCredentialsCookiesAndReferrersAcrossRedirects() async throws {
        let server = try FaviconPrivacyServer()
        try await server.start()
        defer { server.stop() }
        let url = URL(
            string:
                "http://fixture-user:fixture-password@parent.localhost:\(server.port)/credential-icon-redirect#fragment"
        )!
        let data = await BrowserFaviconFallbackLoader.download(url)
        XCTAssertNotNil(data)
        let denied = await BrowserFaviconFallbackLoader.download(
            server.url(host: "parent.localhost", path: "/auth-icon"))
        XCTAssertNil(denied)
        let requests = server.requests
        attach(requests.map(\.description).joined(separator: "\n"), name: "Native credentials wire requests")
        XCTAssertTrue(requests.contains { $0.host.hasPrefix("child.") })
        for request in requests {
            XCTAssertNil(request.headers["referer"], request.description)
            XCTAssertNil(request.headers["cookie"], request.description)
            XCTAssertNil(request.headers["authorization"], request.description)
        }
    }

    func testOversizedIconsAndManifestsStopBeforeTheResponseFinishes() async throws {
        let server = try FaviconPrivacyServer()
        try await server.start()
        defer { server.stop() }
        // The server streams for at least five seconds unless canceled. A
        // post-download size check cannot finish within this budget.
        let start = ContinuousClock.now
        let native = await BrowserFaviconFallbackLoader.download(
            server.url(host: "parent.localhost", path: "/oversized-icon"))
        XCTAssertNil(native)
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))

        let webView = makeWebView()
        try await load(server.url(host: "parent.localhost", path: "/policy/no-referrer"), in: webView)
        try await webView.evaluateJavaScript(
            """
            document.head.innerHTML = '<link rel="manifest" href="/oversized-manifest"><link rel="icon" href="/oversized-icon">';
            """)
        let captureStart = ContinuousClock.now
        let captured = await BrowserFaviconCapture.capture(from: webView)
        XCTAssertNil(captured)
        XCTAssertLessThan(captureStart.duration(to: .now), .seconds(3))
        let requests = server.requests.filter {
            $0.path.hasPrefix("/oversized-") && $0.headers["sec-fetch-dest"] != "manifest"
        }
        XCTAssertTrue(requests.contains { $0.path == "/oversized-manifest" && $0.headers["sec-fetch-mode"] == "cors" })
        XCTAssertTrue(requests.contains { $0.path == "/oversized-manifest" && $0.headers["sec-fetch-mode"] == nil })
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        let navigation = FaviconPrivacyNavigation(trustedPort: url.scheme == "https" ? url.port : nil)
        navigations.append(navigation)
        webView.navigationDelegate = navigation
        webView.load(URLRequest(url: url))
        await fulfillment(of: [navigation.finished], timeout: 15)
        if let error = navigation.error { throw error }
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class FaviconPrivacyNavigation: NSObject, WKNavigationDelegate {
    let finished = XCTestExpectation(description: "Fixture navigation")
    var error: Error?
    let trustedPort: Int?

    init(trustedPort: Int?) { self.trustedPort = trustedPort }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.host == "parent.localhost",
            challenge.protectionSpace.port == trustedPort,
            let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error
        finished.fulfill()
    }
}

/// Real loopback HTTP requests expose cookie/header normalization and redirect
/// behavior that URLProtocol stubs and source assertions cannot establish.
private final class FaviconPrivacyServer: @unchecked Sendable {
    struct Request: CustomStringConvertible {
        let path: String
        let query: String?
        let headers: [String: String]
        var host: String { headers["host", default: ""] }
        var description: String { "\(host)\(path) \(headers)" }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "CrestTests.FaviconPrivacy.HTTP")
    private let lock = NSLock()
    private var captured: [Request] = []
    private let tls: Bool
    var port: UInt16 { listener.port!.rawValue }
    var requests: [Request] { lock.withLock { captured } }

    init(tls: Bool = false) throws {
        self.tls = tls
        let parameters: NWParameters
        if tls {
            let data = try Self.makeTemporaryTLSIdentity()
            var imported: CFArray?
            let status = SecPKCS12Import(
                data as CFData,
                [
                    kSecImportExportPassphrase: "favicon-fixture",
                    kSecImportToMemoryOnly: true,
                ] as CFDictionary, &imported)
            guard status == errSecSuccess,
                let item = (imported as? [[String: Any]])?.first,
                let identity = item[kSecImportItemIdentity as String]
            else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            let options = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(
                options.securityProtocolOptions, sec_identity_create(identity as! SecIdentity)!)
            parameters = NWParameters(tls: options)
        } else {
            parameters = .tcp
        }
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Generate an identity for this loopback listener only. No signing material
    /// is committed, trusted system-wide, or imported into a persistent keychain.
    private static func makeTemporaryTLSIdentity() throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appending(path: "crest-favicon-tls-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for arguments in [
            [
                "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "key.pem", "-out", "cert.pem", "-days", "1",
                "-subj", "/CN=parent.localhost",
            ],
            [
                "pkcs12", "-export", "-inkey", "key.pem", "-in", "cert.pem", "-out", "identity.p12", "-passout",
                "pass:favicon-fixture",
            ],
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "FaviconPrivacyTLSFixture", code: Int(process.terminationStatus))
            }
        }
        return try Data(contentsOf: directory.appending(path: "identity.p12"))
    }

    func url(host: String, path: String) -> URL {
        URL(string: "\(tls ? "https" : "http")://\(host):\(port)\(path)")!
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: queue)
                receive(connection, data: Data())
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, complete, error in
            guard let self else { return }
            let data = data + (chunk ?? Data())
            if let text = String(data: data, encoding: .utf8), text.contains("\r\n\r\n") {
                respond(connection, text: text)
            } else if !complete, error == nil, data.count < 65_536 {
                receive(connection, data: data)
            } else {
                connection.cancel()
            }
        }
    }

    private func respond(_ connection: NWConnection, text: String) {
        let lines = text.components(separatedBy: "\r\n")
        let target = String(lines[0].split(separator: " ")[1])
        let path = URLComponents(string: target)?.path ?? target
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(
                in: .whitespaces)
        }
        let request = Request(path: path, query: URLComponents(string: target)?.query, headers: headers)
        lock.withLock { captured.append(request) }
        if path.hasPrefix("/oversized-") {
            let head =
                "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
            connection.send(
                content: Data(head.utf8),
                completion: .contentProcessed { [weak self] error in
                    if error == nil { self?.stream(connection, remainingChunks: 500) }
                })
            return
        }
        let response = response(for: request)
        // Suppress WebKit's independent manifest loader so the wire transcript
        // measures Crest's capture. Fetch uses connect-src, not manifest-src.
        let policy = response.headers.contains("text/html") ? "Content-Security-Policy: manifest-src 'none'\r\n" : ""
        let head =
            "HTTP/1.1 \(response.status)\r\n\(response.headers)\(policy)Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func stream(_ connection: NWConnection, remainingChunks: Int) {
        guard remainingChunks > 0 else {
            connection.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let chunk = Data("10000\r\n".utf8) + Data(repeating: 65, count: 65_536) + Data("\r\n".utf8)
        connection.send(
            content: chunk,
            completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else {
                    connection.cancel()
                    return
                }
                queue.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    self?.stream(connection, remainingChunks: remainingChunks - 1)
                }
            })
    }

    private func response(for request: Request) -> (status: String, headers: String, body: Data) {
        switch request.path {
        case "/same-site-cookies":
            return (
                "200 OK",
                "Content-Type: text/html\r\nSet-Cookie: strictOther=strict; Path=/; SameSite=Strict\r\nSet-Cookie: laxOther=lax; Path=/; SameSite=Lax\r\n",
                Data("<html>Other site</html>".utf8)
            )
        case "/downgrade-icon":
            let port = request.query!.replacingOccurrences(of: "port=", with: "")
            return (
                "302 Found",
                "Location: http://child.parent.localhost:\(port)/cors-icon\r\nReferrer-Policy: unsafe-url\r\n", Data()
            )
        case "/credential-icon-redirect":
            return (
                "302 Found",
                "Location: http://redirect-user:redirect-password@child.parent.localhost:\(port)/policy-icon#redirect-fragment\r\nSet-Cookie: redirectCookie=unnecessary; Domain=parent.localhost; Path=/\r\n",
                Data()
            )
        case "/auth-icon":
            return ("401 Unauthorized", "WWW-Authenticate: Basic realm=\"Fixture\"\r\n", Data())
        case "/private/page":
            return (
                "200 OK",
                "Content-Type: text/html\r\nReferrer-Policy: no-referrer\r\nSet-Cookie: hostOnly=spaceA; Path=/; HttpOnly; SameSite=Lax\r\nSet-Cookie: domainCookie=domain; Domain=parent.localhost; Path=/\r\nSet-Cookie: privatePath=private; Path=/private\r\nSet-Cookie: secureOnly=secure; Path=/; Secure\r\n",
                Data("<html><head></head><body>Fixture</body></html>".utf8)
            )
        case "/other-space":
            return (
                "200 OK", "Content-Type: text/html\r\nSet-Cookie: spaceB=other; Path=/\r\n",
                Data("<html>Other Space</html>".utf8)
            )
        case "/policy/no-referrer", "/policy/origin":
            let policy = request.path.components(separatedBy: "/").last!
            return (
                "200 OK", "Content-Type: text/html\r\nReferrer-Policy: \(policy)\r\n",
                Data("<html><head><meta name='referrer' content='\(policy)'></head><body>Fixture</body></html>".utf8)
            )
        case "/private/manifest-redirect":
            return ("302 Found", "Location: /private/manifest.json\r\n", Data())
        case "/private/manifest.json":
            guard request.headers["cookie", default: ""].contains("hostOnly=spaceA") else {
                return ("401 Unauthorized", "", Data())
            }
            let manifest = """
                {"icons":[
                  {"src":"http://child.parent.localhost:\(port)/child-icon"},
                  {"src":"/private/cross-site-icon-redirect"},
                  {"src":"/privateer/icon"},
                  {"src":"/private/icon-redirect"}
                ]}
                """
            return ("200 OK", "Content-Type: application/manifest+json\r\n", Data(manifest.utf8))
        case "/private/cross-site-icon-redirect":
            return (
                "302 Found",
                "Location: http://other.localhost:\(port)/same-site-icon\r\nReferrer-Policy: unsafe-url\r\n", Data()
            )
        case "/private/icon-redirect":
            return ("302 Found", "Location: /public/icon\r\nReferrer-Policy: unsafe-url\r\n", Data())
        case "/public/icon":
            guard request.headers["cookie", default: ""].contains("hostOnly=spaceA") else {
                return ("401 Unauthorized", "", Data())
            }
            return iconResponse()
        case "/policy-icon-redirect":
            return (
                "302 Found",
                "Location: /policy-icon\r\nReferrer-Policy: unsafe-url\r\nSet-Cookie: redirectCookie=unnecessary; Path=/\r\n",
                Data()
            )
        case "/policy-manifest-redirect":
            return ("302 Found", "Location: /policy-manifest.json\r\nReferrer-Policy: unsafe-url\r\n", Data())
        case "/policy-manifest.json":
            return (
                "200 OK", "Content-Type: application/manifest+json\r\n",
                Data(#"{"icons":[{"src":"policy-manifest-icon-redirect"}]}"#.utf8)
            )
        case "/policy-manifest-icon-redirect":
            return ("302 Found", "Location: /policy-manifest-icon\r\nReferrer-Policy: unsafe-url\r\n", Data())
        case "/cors-icon":
            let icon = iconResponse()
            return (icon.status, icon.headers + "Access-Control-Allow-Origin: *\r\n", icon.body)
        case "/policy-icon":
            return iconResponse()
        default:
            return ("404 Not Found", "", Data())
        }
    }

    private func iconResponse() -> (status: String, headers: String, body: Data) {
        (
            "200 OK", "Content-Type: image/svg+xml\r\n",
            Data(
                #"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="blue"/></svg>"#
                    .utf8)
        )
    }
}

import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerNetworkTests: XCTestCase {
    func testAFetchReportsAChromeRequestResponseAndBody() async throws {
        try await withNetwork { network, fixture in
            _ = try await fixture.page.evaluateJavaScript(
                """
                globalThis.crestFetched = null;
                const blob = new Blob(['crest-network-body'], {type: 'text/plain'});
                globalThis.crestBlobURL = URL.createObjectURL(blob);
                fetch(crestBlobURL)
                    .then(response => response.text())
                    .then(text => { crestFetched = text; }, error => { crestFetched = String(error); });
                undefined
                """)
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                (try? await fixture.page.evaluateJavaScript("globalThis.crestFetched")) as? String
                    == "crest-network-body"
            }
            try await fixture.waitForEvent("Network.requestWillBeSent") { parameters in
                ((parameters["request"] as? [String: Any])?["url"] as? String)?.hasPrefix("blob:") == true
            }
            let sent = try XCTUnwrap(
                fixture.all("Network.requestWillBeSent").last {
                    (($0["request"] as? [String: Any])?["url"] as? String)?.hasPrefix("blob:") == true
                })
            let requestID = try XCTUnwrap(sent["requestId"] as? String)
            let request = try XCTUnwrap(sent["request"] as? [String: Any])
            XCTAssertEqual(request["method"] as? String, "GET")
            XCTAssertNotNil(request["headers"] as? [String: Any])
            XCTAssertEqual(request["initialPriority"] as? String, "Medium")
            XCTAssertNotNil(request["referrerPolicy"] as? String)
            XCTAssertNotNil(sent["documentURL"] as? String)
            XCTAssertEqual(sent["redirectHasExtraInfo"] as? Bool, false)
            XCTAssertGreaterThan(try XCTUnwrap(sent["timestamp"] as? Double), 0)
            XCTAssertGreaterThan(try XCTUnwrap(sent["wallTime"] as? Double), 1_600_000_000)
            let initiator = try XCTUnwrap(sent["initiator"] as? [String: Any])
            XCTAssertEqual(initiator["type"] as? String, "script")
            XCTAssertEqual(sent["type"] as? String, "Fetch")

            try await fixture.waitForEvent("Network.responseReceived") { $0["requestId"] as? String == requestID }
            let received = try XCTUnwrap(
                fixture.all("Network.responseReceived").first { $0["requestId"] as? String == requestID })
            XCTAssertEqual(received["hasExtraInfo"] as? Bool, false)
            XCTAssertEqual(received["type"] as? String, "Fetch")
            let response = try XCTUnwrap(received["response"] as? [String: Any])
            XCTAssertEqual(response["status"] as? Int, 200)
            XCTAssertEqual(response["mimeType"] as? String, "text/plain")
            XCTAssertNotNil(response["headers"] as? [String: Any])
            XCTAssertEqual(response["connectionReused"] as? Bool, false)
            XCTAssertNotNil(response["securityState"] as? String)

            try await fixture.waitForEvent("Network.loadingFinished") { $0["requestId"] as? String == requestID }
            let body = try await network.execute("Network.getResponseBody", parameters: ["requestId": requestID])
            XCTAssertEqual(body["body"] as? String, "crest-network-body")
            XCTAssertEqual(body["base64Encoded"] as? Bool, false)
        }
    }

    func testARefusedRequestReportsLoadingFailedWithItsResourceType() async throws {
        try await withNetwork { network, fixture in
            _ = try await fixture.page.evaluateJavaScript(
                """
                globalThis.crestRefused = null;
                fetch('https://127.0.0.1:49221/crest-refused')
                    .then(() => { crestRefused = 'unexpected'; }, () => { crestRefused = 'refused'; });
                undefined
                """)
            try await fixture.waitForEvent("Network.loadingFailed")
            let failed = try XCTUnwrap(fixture.first("Network.loadingFailed"))
            XCTAssertFalse(try XCTUnwrap(failed["requestId"] as? String).isEmpty)
            XCTAssertGreaterThan(try XCTUnwrap(failed["timestamp"] as? Double), 0)
            XCTAssertFalse(try XCTUnwrap(failed["errorText"] as? String).isEmpty)
            // Chrome repeats the resource type on failure; WebKit states it once.
            XCTAssertEqual(failed["type"] as? String, "Fetch")
        }
    }

    func testDocumentNavigationReportsTheDocumentTypeAndDisableStopsEvents() async throws {
        try await withNetwork { network, fixture in
            fixture.page.load(URLRequest(url: try XCTUnwrap(URL(string: "https://crest.test/domain?network"))))
            try await fixture.waitForEvent("Network.requestWillBeSent") { $0["type"] as? String == "Document" }
            network.disable()
            let count = fixture.all("Network.requestWillBeSent").count
            _ = try? await fixture.page.evaluateJavaScript(
                "fetch('https://127.0.0.1:49222/crest-while-disabled').catch(() => {}); undefined")
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(fixture.all("Network.requestWillBeSent").count, count)
        }
    }

    func testUnsupportedNetworkCommandsAreRefused() async throws {
        try await withNetwork { network, _ in
            for method in [
                "Network.setExtraHTTPHeaders", "Network.setCacheDisabled", "Network.emulateNetworkConditions",
            ] {
                do {
                    _ = try await network.execute(method, parameters: [:])
                    XCTFail("An unimplemented Network command must report unsupported: \(method)")
                } catch BrowserChromeDebuggerProtocolError.unsupportedCommand {}
            }
        }
    }

    private func withNetwork(
        _ operation: (BrowserChromeDebuggerNetwork, BrowserChromeDebuggerDomainFixture) async throws -> Void
    ) async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make()
        defer { fixture.tearDown() }
        let network = BrowserChromeDebuggerNetwork(connection: fixture.connection)
        network.onEvent = fixture.recorder()
        fixture.route([{ [weak network] method, parameters in network?.receive(method, parameters: parameters) }])
        _ = try await network.execute("Network.enable", parameters: [:])
        try await operation(network, fixture)
    }
}

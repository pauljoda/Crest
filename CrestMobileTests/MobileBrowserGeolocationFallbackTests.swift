import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserGeolocationBridgeTests: XCTestCase {
    func testSecurePageReceivesPositionThroughSharedBridge() async throws {
        let url = try XCTUnwrap(URL(string: "https://location.crest.test/"))
        let origin = try XCTUnwrap(BrowserSiteOrigin(url: url))
        let tab = BrowserTab(title: "Location", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Mobile",
            symbol: "location",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let permissionCenter = BrowserSitePermissionCenter()
        permissionCenter.setDecision(
            .grantPersistently,
            for: .location,
            origin: origin,
            in: space.id
        )
        let service = TestMobileBrowserGeolocationService()
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            permissionCenter: permissionCenter,
            geolocationService: service,
            websiteDataStore: .nonPersistent(),
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
        defer { page.prepareForSpaceDeletion() }

        page.webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: "<!doctype html><title>Location fixture</title>"
        )
        try await waitUntil("the mobile geolocation bridge") {
            try await self.permissionState(in: page.webView) == "granted"
        }

        _ = try await page.webView.callAsyncJavaScript(
            """
            globalThis.crestLocationResult = null;
            navigator.geolocation.getCurrentPosition(
              position => { globalThis.crestLocationResult = position.coords.longitude; },
              error => { globalThis.crestLocationResult = `error-${error.code}`; }
            );
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil("the mobile native current-location request") {
            service.requests.count == 1
        }
        let request = try XCTUnwrap(service.requests.first?.value)
        request(.success(Self.position))

        try await waitUntil("the mobile page location callback") {
            try await self.doubleResult(
                in: page.webView,
                script: "return globalThis.crestLocationResult;"
            ) == Self.position.longitude
        }
    }

    private static let position = BrowserGeolocationPosition(
        latitude: 41.8781,
        longitude: -87.6298,
        accuracy: 12,
        altitude: nil,
        altitudeAccuracy: nil,
        heading: nil,
        speed: nil,
        timestamp: 1_786_944_000_000
    )

    private func permissionState(in webView: WKWebView) async throws -> String? {
        try await webView.callAsyncJavaScript(
            "return (await navigator.permissions.query({ name: 'geolocation' })).state;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    private func doubleResult(in webView: WKWebView, script: String) async throws -> Double? {
        try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Double
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description).")
    }
}

@MainActor
private final class TestMobileBrowserGeolocationService: BrowserGeolocationServicing {
    typealias Receive =
        @MainActor (
            Result<BrowserGeolocationPosition, BrowserGeolocationError>
        ) -> Void

    var requests: [String: Receive] = [:]

    func currentAuthorization() -> BrowserGeolocationSystemAuthorization { .authorized }

    func requestAuthorization() async -> BrowserGeolocationSystemAuthorization { .authorized }

    func requestCurrentPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping Receive
    ) {
        requests[identifier] = receive
    }

    func startWatchingPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping Receive
    ) {
        requests[identifier] = receive
    }

    func cancel(identifier: String) { requests.removeValue(forKey: identifier) }

    func cancelAll() { requests.removeAll() }
}

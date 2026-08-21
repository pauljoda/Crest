import Foundation
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
        // Every step below runs script in the fixture, and script asked of a
        // page that has not finished loading is answered by whichever document
        // is still standing — or not answered at all while WebKit swaps one for
        // the other. The page reports its own navigations, so gate on that
        // rather than letting the first question double as the load wait.
        try await waitUntil("the location fixture to finish loading") {
            page.completedNavigationCount == 1
        }
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
        // The service is what the bridge reaches, so let it say when it was
        // reached instead of polling for it: the arrival is signalled, and no
        // budget has to cover how long a saturated machine needs to carry one
        // message out of the page.
        await service.waitUntilRequestCount(1)
        let request = try XCTUnwrap(service.requests.first?.value)
        request(.success(Self.position))

        // Nothing on this side can signal the page's own callback running, so
        // this one still polls. What it waits for is WebKit scheduling script in
        // an already-loaded document — the shortest step in the test — under the
        // same budget every other WebKit-backed mobile suite gives one.
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

    /// Polls `condition` until it holds, and stops the test when it never does.
    ///
    /// Eight seconds is what every other WebKit-backed mobile suite here gives a
    /// page, and giving up throws rather than merely recording a failure: a
    /// fixture that never loaded cannot answer the questions that follow either,
    /// and asking them anyway buries the one failure that explains the run.
    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(8),
        condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description).")
        throw MobileGeolocationWaitTimeout(subject: description)
    }
}

private struct MobileGeolocationWaitTimeout: LocalizedError {
    let subject: String

    var errorDescription: String? { "Timed out waiting for \(subject)." }
}

@MainActor
private final class TestMobileBrowserGeolocationService: BrowserGeolocationServicing {
    typealias Receive =
        @MainActor (
            Result<BrowserGeolocationPosition, BrowserGeolocationError>
        ) -> Void

    var requests: [String: Receive] = [:]

    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func currentAuthorization() -> BrowserGeolocationSystemAuthorization { .authorized }

    func requestAuthorization() async -> BrowserGeolocationSystemAuthorization { .authorized }

    func requestCurrentPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping Receive
    ) {
        requests[identifier] = receive
        announceRequest()
    }

    func startWatchingPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping Receive
    ) {
        requests[identifier] = receive
        announceRequest()
    }

    /// Suspends until the bridge has made its `count`-th native request.
    func waitUntilRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    private func announceRequest() {
        let arrivedCount = requests.count
        let readyWaiters = requestWaiters.filter { $0.count <= arrivedCount }
        requestWaiters.removeAll { $0.count <= arrivedCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }

    func cancel(identifier: String) { requests.removeValue(forKey: identifier) }

    func cancelAll() { requests.removeAll() }
}

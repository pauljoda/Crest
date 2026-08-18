import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserGeolocationBridgeTests: XCTestCase {
    func testSecurePageReceivesPositionAndCanCancelWatch() async throws {
        let fixture = try makeFixture()
        defer { fixture.page.prepareForSpaceDeletion() }

        fixture.page.webView.loadSimulatedRequest(
            URLRequest(url: fixture.url),
            responseHTML: "<!doctype html><title>Location fixture</title>"
        )
        try await waitUntil("the geolocation bridge to report granted permission") {
            try await self.permissionState(in: fixture.page.webView) == "granted"
        }

        _ = try await fixture.page.webView.callAsyncJavaScript(
            """
            globalThis.crestLocationResult = null;
            navigator.geolocation.getCurrentPosition(
              position => { globalThis.crestLocationResult = position.coords.latitude; },
              error => { globalThis.crestLocationResult = `error-${error.code}`; },
              { enableHighAccuracy: true, maximumAge: 2500 }
            );
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil("the native current-location request") {
            fixture.service.currentRequests.count == 1
        }
        let request = try XCTUnwrap(fixture.service.currentRequests.first)
        XCTAssertTrue(request.value.options.enablesHighAccuracy)
        XCTAssertEqual(request.value.options.maximumAge, 2.5)

        request.value.receive(.success(Self.position))
        try await waitUntil("the page location callback") {
            try await self.doubleResult(
                in: fixture.page.webView,
                script: "return globalThis.crestLocationResult;"
            ) == Self.position.latitude
        }

        _ = try await fixture.page.webView.callAsyncJavaScript(
            """
            globalThis.crestWatchID = navigator.geolocation.watchPosition(() => {});
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil("the native watch request") {
            fixture.service.watchRequests.count == 1
        }
        let watchIdentifier = try XCTUnwrap(fixture.service.watchRequests.keys.first)

        _ = try await fixture.page.webView.callAsyncJavaScript(
            "navigator.geolocation.clearWatch(globalThis.crestWatchID);",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil("the native watch cancellation") {
            fixture.service.cancelledIdentifiers.contains(watchIdentifier)
        }
    }

    func testSystemSettingsRecoveryResumesOriginalPageRequest() async throws {
        let fixture = try makeFixture(
            systemAuthorization: .denied,
            recoversSystemAuthorization: true
        )
        defer { fixture.page.prepareForSpaceDeletion() }

        fixture.page.webView.loadSimulatedRequest(
            URLRequest(url: fixture.url),
            responseHTML: "<!doctype html><title>Location recovery fixture</title>"
        )
        try await waitUntil("the bridge to expose the effective system block") {
            try await self.permissionState(in: fixture.page.webView) == "denied"
        }

        _ = try await fixture.page.webView.callAsyncJavaScript(
            """
            globalThis.crestRecoveredLocation = null;
            navigator.geolocation.getCurrentPosition(
              position => { globalThis.crestRecoveredLocation = position.coords.latitude; },
              error => { globalThis.crestRecoveredLocation = `error-${error.code}`; }
            );
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil("the same request to reach Core Location after recovery") {
            fixture.service.recoveryCount == 1
                && fixture.service.currentRequests.count == 1
        }
        let request = try XCTUnwrap(fixture.service.currentRequests.first?.value)
        request.receive(.success(Self.position))

        try await waitUntil("the original page callback after system recovery") {
            try await self.doubleResult(
                in: fixture.page.webView,
                script: "return globalThis.crestRecoveredLocation;"
            ) == Self.position.latitude
        }
        let recoveredPermission = try await permissionState(
            in: fixture.page.webView
        )
        XCTAssertEqual(recoveredPermission, "granted")
    }

    func testOriginPolicyRequiresSecureOrLoopbackHTTPOrigin() throws {
        let secureOrigin = try XCTUnwrap(
            BrowserSiteOrigin(
                url: try XCTUnwrap(URL(string: "https://maps.example"))
            )
        )
        let loopbackOrigin = try XCTUnwrap(
            BrowserSiteOrigin(
                url: try XCTUnwrap(URL(string: "http://localhost:8080"))
            )
        )
        let insecureOrigin = try XCTUnwrap(
            BrowserSiteOrigin(
                url: try XCTUnwrap(URL(string: "http://maps.example"))
            )
        )

        XCTAssertTrue(
            BrowserGeolocationOriginPolicy.allows(secureOrigin)
        )
        XCTAssertTrue(
            BrowserGeolocationOriginPolicy.allows(loopbackOrigin)
        )
        XCTAssertFalse(
            BrowserGeolocationOriginPolicy.allows(insecureOrigin)
        )
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

    private func makeFixture(
        systemAuthorization: BrowserGeolocationSystemAuthorization = .authorized,
        recoversSystemAuthorization: Bool = false
    ) throws -> (
        page: BrowserPage,
        service: TestBrowserGeolocationService,
        url: URL
    ) {
        let url = try XCTUnwrap(URL(string: "https://location.crest.test/"))
        let origin = try XCTUnwrap(BrowserSiteOrigin(url: url))
        let space = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        let permissionCenter = BrowserSitePermissionCenter()
        permissionCenter.setDecision(
            .grantPersistently,
            for: .location,
            origin: origin,
            in: space.id
        )
        let service = TestBrowserGeolocationService(
            authorization: systemAuthorization
        )
        let configuration = BrowserPageConfiguration.make(
            for: space.profile,
            websiteDataStore: .nonPersistent()
        )
        let page = BrowserPage(
            configuration: configuration,
            dialogPresenter: BrowserDialogPresenter(),
            downloadCenter: BrowserDownloadCenter(),
            permissionCenter: permissionCenter,
            geolocationService: service,
            recoverGeolocationSystemAuthorization: {
                service.recoveryCount += 1
                if recoversSystemAuthorization {
                    service.authorization = .authorized
                }
            },
            spaceID: space.id,
            profileID: space.profile.id,
            spaceName: space.name,
            openNewTab: { _ in }
        )
        return (page, service, url)
    }

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
private final class TestBrowserGeolocationService: BrowserGeolocationServicing {
    struct Request {
        let options: BrowserGeolocationRequestOptions
        let receive: @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    }

    var currentRequests: [String: Request] = [:]
    var watchRequests: [String: Request] = [:]
    var cancelledIdentifiers: Set<String> = []
    var authorization: BrowserGeolocationSystemAuthorization
    var recoveryCount = 0

    init(authorization: BrowserGeolocationSystemAuthorization) {
        self.authorization = authorization
    }

    func currentAuthorization() -> BrowserGeolocationSystemAuthorization {
        authorization
    }

    func requestAuthorization() async -> BrowserGeolocationSystemAuthorization {
        authorization
    }

    func requestCurrentPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    ) {
        currentRequests[identifier] = Request(options: options, receive: receive)
    }

    func startWatchingPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    ) {
        watchRequests[identifier] = Request(options: options, receive: receive)
    }

    func cancel(identifier: String) {
        currentRequests.removeValue(forKey: identifier)
        watchRequests.removeValue(forKey: identifier)
        cancelledIdentifiers.insert(identifier)
    }

    func cancelAll() {
        currentRequests.removeAll()
        watchRequests.removeAll()
    }
}

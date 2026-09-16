import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserGeolocationBridgeTests: XCTestCase {
    func testDismissingLocationPromptKeepsAskAndRememberedAllowSkipsTheNextPrompt() async throws {
        let fixture = try makeFixture()
        defer { fixture.page.prepareForSpaceDeletion() }
        let origin = try XCTUnwrap(BrowserSiteOrigin(url: fixture.url))
        fixture.page.permissionCenter.setDecision(.ask, for: .location, origin: origin, in: fixture.page.spaceID)
        fixture.page.sitePermissionRequests.setPresentationAvailable(true)
        fixture.page.webView.loadSimulatedRequest(URLRequest(url: fixture.url), responseHTML: "<title>Location</title>")
        try await waitUntil("the loaded location document") {
            guard fixture.page.webView.url == fixture.url, !fixture.page.webView.isLoading else { return false }
            return try await fixture.page.webView.evaluateJavaScript("Boolean(globalThis.__crestGeolocationBridge)")
                as? Bool == true
        }
        try await waitUntil("the location bridge") {
            try await self.permissionState(in: fixture.page.webView) == "prompt"
        }
        func requestPosition() async throws {
            _ = try await fixture.page.webView.evaluateJavaScript(
                "globalThis.locationError = null; navigator.geolocation.getCurrentPosition(() => {}, e => { globalThis.locationError = e.code; });"
            )
        }
        try await requestPosition()
        try await waitUntil("the site location prompt") { fixture.page.sitePermissionRequests.current != nil }
        XCTAssertEqual(fixture.page.sitePermissionRequests.current?.permission, .location)
        fixture.page.sitePermissionRequests.cancelAll()
        try await waitUntil("the dismissed request callback") {
            try await self.doubleResult(in: fixture.page.webView, script: "return globalThis.locationError;") == 1
        }
        XCTAssertEqual(
            fixture.page.permissionCenter.decision(for: .location, origin: origin, in: fixture.page.spaceID), .ask)
        XCTAssertTrue(fixture.service.currentRequests.isEmpty)
        try await requestPosition()
        try await waitUntil("a new location request") { fixture.page.sitePermissionRequests.current != nil }
        fixture.page.sitePermissionRequests.resolve(
            try XCTUnwrap(fixture.page.sitePermissionRequests.current?.id), response: .grantPersistently)
        try await waitUntil("the authorized location request") { fixture.service.currentRequests.count == 1 }
        try await requestPosition()
        try await waitUntil("the next request without another prompt") { fixture.service.currentRequests.count == 2 }
        XCTAssertNil(fixture.page.sitePermissionRequests.current)
    }

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

    func testRevocationStopsRequestsAndRejectsLateCallbacksAfterRegrant() async throws {
        for action in Revocation.allCases {
            let fixture = try makeFixture()
            defer { fixture.page.prepareForSpaceDeletion() }
            let origin = try XCTUnwrap(BrowserSiteOrigin(url: fixture.url))
            if action == .sessionReset {
                fixture.page.permissionCenter.setDecision(
                    .grantForSession, for: .location, origin: origin, in: fixture.page.spaceID
                )
            }
            try await loadRequests(in: fixture)
            let current = try XCTUnwrap(fixture.service.currentRequests.first?.value)
            let watch = try XCTUnwrap(fixture.service.watchRequests.first?.value)
            switch action {
            case .block, .ask:
                fixture.page.permissionCenter.setDecision(
                    action == .block ? .denyPersistently : .ask,
                    for: .location, origin: origin, in: fixture.page.spaceID
                )
            case .originReset:
                fixture.page.permissionCenter.reset(recordID: try XCTUnwrap(
                    fixture.page.permissionCenter.records(in: fixture.page.spaceID).first?.id
                ))
            case .spaceReset:
                fixture.page.permissionCenter.reset(spaceID: fixture.page.spaceID)
            case .sessionReset:
                fixture.page.permissionCenter.resetSession()
            }
            XCTAssertTrue(fixture.service.currentRequests.isEmpty, "\(action) cancels in-flight positions synchronously")
            XCTAssertTrue(fixture.service.watchRequests.isEmpty, "\(action) stops the native watch synchronously")
            fixture.page.permissionCenter.setDecision(
                .grantPersistently, for: .location, origin: origin, in: fixture.page.spaceID
            )
            current.receive(.success(Self.position))
            watch.receive(.success(Self.position))
            try await expectCounts(in: fixture, successes: 0, denials: 2)
            _ = try await fixture.page.webView.evaluateJavaScript(
                "navigator.geolocation.getCurrentPosition(success, failure);"
            )
            try await waitUntil("a fresh request after regrant") { fixture.service.currentRequests.count == 1 }
            try XCTUnwrap(fixture.service.currentRequests.first?.value).receive(.success(Self.position))
            try await expectCounts(in: fixture, successes: 1, denials: 2)
        }
    }

    func testOriginAndSpaceResetLeaveUnrelatedGrantsRunning() async throws {
        let center = BrowserSitePermissionCenter()
        let first = try makeFixture(center: center)
        let otherOrigin = try makeFixture(center: center, url: URL(string: "https://other.crest.test/"))
        let otherSpace = try makeFixture(center: center, space: BrowserSession.preview.spaces.last)
        let fixtures = [first, otherOrigin, otherSpace]
        defer { fixtures.forEach { $0.page.prepareForSpaceDeletion() } }
        XCTAssertNotEqual(first.page.spaceID, otherSpace.page.spaceID)
        for fixture in fixtures { try await loadRequests(in: fixture) }
        let origin = try XCTUnwrap(BrowserSiteOrigin(url: first.url))
        center.setDecision(.denyPersistently, for: .camera, origin: origin, in: first.page.spaceID)
        XCTAssertTrue(fixtures.allSatisfy { $0.service.watchRequests.count == 1 })
        center.reset(recordID: try XCTUnwrap(center.records(in: first.page.spaceID).first {
            $0.origin == origin && $0.permission == .location
        }?.id))
        XCTAssertTrue(first.service.watchRequests.isEmpty)
        XCTAssertEqual(otherOrigin.service.watchRequests.count, 1)
        XCTAssertEqual(otherSpace.service.watchRequests.count, 1)
        center.reset(spaceID: first.page.spaceID)
        XCTAssertTrue(otherOrigin.service.watchRequests.isEmpty)
        let surviving = try XCTUnwrap(otherSpace.service.watchRequests.first?.value)
        surviving.receive(.success(Self.position))
        try await expectCounts(in: otherSpace, successes: 1, denials: 0)
        try await expectCounts(in: first, successes: 0, denials: 2)
        try await expectCounts(in: otherOrigin, successes: 0, denials: 2)
    }

    func testAllowOnceSurvivesOrdinaryUseButAskAgainRevokesItAndFreshRequestsAsk() async throws {
        let fixture = try makeFixture()
        defer { fixture.page.prepareForSpaceDeletion() }
        let origin = try XCTUnwrap(BrowserSiteOrigin(url: fixture.url))
        fixture.page.permissionCenter.setDecision(.ask, for: .location, origin: origin, in: fixture.page.spaceID)
        fixture.page.sitePermissionRequests.setPresentationAvailable(true)
        try await loadRequests(in: fixture, startsAuthorized: false, watchOnly: true)
        try await resolvePrompt(in: fixture, response: .allowOnce)
        try await waitUntil("the once-authorized watch") { fixture.service.watchRequests.count == 1 }
        let watch = try XCTUnwrap(fixture.service.watchRequests.first?.value)
        watch.receive(.success(Self.position))
        try await expectCounts(in: fixture, successes: 1, denials: 0)
        let state = try await permissionState(in: fixture.page.webView)
        XCTAssertEqual(state, "prompt", "Allow Once must not create a stored grant")
        fixture.page.permissionCenter.setDecision(.ask, for: .location, origin: origin, in: fixture.page.spaceID)
        XCTAssertTrue(fixture.service.watchRequests.isEmpty)
        watch.receive(.success(Self.position))
        try await expectCounts(in: fixture, successes: 1, denials: 1)
        _ = try await fixture.page.webView.evaluateJavaScript(
            "navigator.geolocation.getCurrentPosition(success, failure);"
        )
        try await resolvePrompt(in: fixture, response: .denyOnce)
        try await expectCounts(in: fixture, successes: 1, denials: 2)
        fixture.page.permissionCenter.setDecision(.denyPersistently, for: .location, origin: origin, in: fixture.page.spaceID)
        _ = try await fixture.page.webView.evaluateJavaScript(
            "navigator.geolocation.getCurrentPosition(success, failure);"
        )
        try await expectCounts(in: fixture, successes: 1, denials: 3)
        XCTAssertNil(fixture.page.sitePermissionRequests.current)
        XCTAssertTrue(fixture.service.currentRequests.isEmpty)
    }

    func testRevocationDuringSiteOrSystemConsentCannotPersistOrStartOldRequest() async throws {
        for awaitsSystem in [false, true] {
            let fixture = try makeFixture(systemAuthorization: awaitsSystem ? .notDetermined : .authorized)
            defer { fixture.page.prepareForSpaceDeletion() }
            let origin = try XCTUnwrap(BrowserSiteOrigin(url: fixture.url))
            fixture.page.permissionCenter.setDecision(.ask, for: .location, origin: origin, in: fixture.page.spaceID)
            fixture.page.sitePermissionRequests.setPresentationAvailable(true)
            fixture.service.delaysAuthorization = awaitsSystem
            try await loadRequests(in: fixture, startsAuthorized: false, watchOnly: true)
            try await waitUntil("the site consent request") { fixture.page.sitePermissionRequests.current != nil }
            let promptID = try XCTUnwrap(fixture.page.sitePermissionRequests.current?.id)
            if awaitsSystem {
                fixture.page.sitePermissionRequests.resolve(promptID, response: .grantPersistently)
                try await waitUntil("the OS consent request") { fixture.service.authorizationContinuation != nil }
            }
            fixture.page.permissionCenter.reset(spaceID: fixture.page.spaceID)
            try await expectCounts(in: fixture, successes: 0, denials: 1)
            if awaitsSystem {
                fixture.service.authorization = .authorized
                fixture.service.authorizationContinuation?.resume(returning: .authorized)
                fixture.service.authorizationContinuation = nil
            } else {
                fixture.page.sitePermissionRequests.resolve(promptID, response: .grantPersistently)
            }
            // Drain the resumed authorization task before examining its effects.
            _ = try await permissionState(in: fixture.page.webView)
            XCTAssertTrue(fixture.service.watchRequests.isEmpty)
            XCTAssertEqual(fixture.page.permissionCenter.decision(for: .location, origin: origin, in: fixture.page.spaceID), .ask)
            _ = try await fixture.page.webView.evaluateJavaScript("navigator.geolocation.watchPosition(success, failure);")
            try await resolvePrompt(in: fixture, response: .allowOnce)
            try await waitUntil("fresh consent after withdrawal") { fixture.service.watchRequests.count == 1 }
            try XCTUnwrap(fixture.service.watchRequests.first?.value).receive(.success(Self.position))
            try await expectCounts(in: fixture, successes: 1, denials: 1)
        }
    }

    func testQueuedDeliveryRechecksSiteAndSystemAuthorization() async throws {
        for revokesSystem in [false, true] {
            let fixture = try makeFixture()
            defer { fixture.page.prepareForSpaceDeletion() }
            try await loadRequests(in: fixture)
            let current = try XCTUnwrap(fixture.service.currentRequests.first?.value)
            let watch = try XCTUnwrap(fixture.service.watchRequests.first?.value)
            current.receive(.success(Self.position))
            watch.receive(.success(Self.position))
            // Revoke before the asynchronous WebKit delivery tasks get a turn.
            if revokesSystem { fixture.service.authorization = .denied }
            else { fixture.page.permissionCenter.reset(spaceID: fixture.page.spaceID) }
            try await expectCounts(in: fixture, successes: 0, denials: 2)
            XCTAssertTrue(fixture.service.currentRequests.isEmpty)
            XCTAssertTrue(fixture.service.watchRequests.isEmpty)
        }
    }

    func testFrameNavigationAndClearWatchDoNotAffectSiblingRequestsOrDeliverOldReplies() async throws {
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { request in
            let frame = request.path == "/" ? "<iframe src='/child'></iframe>" : ""
            let html = """
                <!doctype html><title>Frame ownership</title><script>
                globalThis.successes = 0;
                globalThis.watchID = navigator.geolocation.watchPosition(() => { successes++; });
                </script>\(frame)
                """
            return ("200 OK", "Content-Type: text/html\r\n", Data(html.utf8))
        }
        try await server.start()
        defer { server.stop() }
        let fixture = try makeFixture(url: server.url(host: "127.0.0.1", path: "/"))
        defer { fixture.page.prepareForSpaceDeletion() }
        fixture.page.webView.load(URLRequest(url: fixture.url))
        try await waitUntil("watches with colliding JS identifiers in two frames") { fixture.service.watchRequests.count == 2 }
        let original = fixture.service.watchRequests
        for request in original.values { request.receive(.success(Self.position)) }
        try await waitUntil("one position in each owning frame") {
            let values = try await fixture.page.webView.evaluateJavaScript("[successes, frames[0].successes]") as? [Double]
            return values == [1, 1]
        }
        _ = try await fixture.page.webView.evaluateJavaScript("document.querySelector('iframe').src = '/replacement';")
        try await waitUntil("only the child document watch to be replaced") {
            fixture.service.watchRequests.count == 2 && Set(fixture.service.watchRequests.keys) != Set(original.keys)
        }
        let parentID = try XCTUnwrap(Set(original.keys).intersection(fixture.service.watchRequests.keys).first)
        let oldChildID = try XCTUnwrap(Set(original.keys).subtracting(fixture.service.watchRequests.keys).first)
        let replacementID = try XCTUnwrap(Set(fixture.service.watchRequests.keys).subtracting(original.keys).first)
        let replacement = try XCTUnwrap(fixture.service.watchRequests[replacementID])
        try XCTUnwrap(original[oldChildID]).receive(.success(Self.position))
        replacement.receive(.success(Self.position))
        try await waitUntil("only the replacement's own reply") {
            let values = try await fixture.page.webView.evaluateJavaScript("[successes, frames[0].successes]") as? [Double]
            return values == [1, 1]
        }
        _ = try await fixture.page.webView.evaluateJavaScript("frames[0].navigator.geolocation.clearWatch(frames[0].watchID);")
        try await waitUntil("clearWatch to cancel only its frame") { Set(fixture.service.watchRequests.keys) == [parentID] }
        replacement.receive(.success(Self.position))
        try XCTUnwrap(original[parentID]).receive(.success(Self.position))
        try await waitUntil("the sibling watch to remain live") {
            let values = try await fixture.page.webView.evaluateJavaScript("[successes, frames[0].successes]") as? [Double]
            return values == [2, 1]
        }
        fixture.page.webView.loadSimulatedRequest(
            URLRequest(url: fixture.url), responseHTML: "<title>Next document</title><script>globalThis.successes = 0;</script>"
        )
        try await waitUntil("main-document navigation teardown") {
            fixture.service.watchRequests.isEmpty && !fixture.page.webView.isLoading
        }
        try XCTUnwrap(original[parentID]).receive(.success(Self.position))
        let successes = try await doubleResult(in: fixture.page.webView, script: "return successes;")
        XCTAssertEqual(successes, 0)
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

    private enum Revocation: CaseIterable { case block, ask, originReset, spaceReset, sessionReset }
    private typealias Fixture = (page: BrowserPage, service: TestBrowserGeolocationService, url: URL)

    private func loadRequests(in fixture: Fixture, startsAuthorized: Bool = true, watchOnly: Bool = false) async throws {
        fixture.page.webView.loadSimulatedRequest(URLRequest(url: fixture.url), responseHTML: "<title>Location</title>")
        try await waitUntil("the location document") {
            guard fixture.page.webView.url == fixture.url, !fixture.page.webView.isLoading else { return false }
            return try await self.permissionState(in: fixture.page.webView) == (startsAuthorized ? "granted" : "prompt")
        }
        _ = try await fixture.page.webView.evaluateJavaScript("""
            globalThis.successes = 0; globalThis.denials = 0;
            globalThis.success = () => { globalThis.successes++; };
            globalThis.failure = e => { if (e.code === 1) globalThis.denials++; };
            globalThis.watchID = navigator.geolocation.watchPosition(success, failure);
            """)
        if !watchOnly {
            _ = try await fixture.page.webView.evaluateJavaScript("navigator.geolocation.getCurrentPosition(success, failure);")
        }
        if startsAuthorized {
            try await waitUntil("the native requests") {
                fixture.service.watchRequests.count == 1 && (watchOnly || fixture.service.currentRequests.count == 1)
            }
        }
    }

    private func expectCounts(in fixture: Fixture, successes: Double, denials: Double) async throws {
        try await waitUntil("\(denials) permission denials and \(successes) successes") {
            let counts = try await fixture.page.webView.evaluateJavaScript("[globalThis.successes, globalThis.denials]") as? [Double]
            return counts == [successes, denials]
        }
    }

    private func resolvePrompt(in fixture: Fixture, response: BrowserPagePermissionController.Response) async throws {
        try await waitUntil("a fresh site consent prompt") { fixture.page.sitePermissionRequests.current != nil }
        fixture.page.sitePermissionRequests.resolve(try XCTUnwrap(fixture.page.sitePermissionRequests.current?.id), response: response)
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
        recoversSystemAuthorization: Bool = false,
        center: BrowserSitePermissionCenter? = nil,
        url: URL? = nil,
        space: BrowserSpace? = nil
    ) throws -> Fixture {
        let url = try XCTUnwrap(url ?? URL(string: "https://location.crest.test/"))
        let origin = try XCTUnwrap(BrowserSiteOrigin(url: url))
        let space = try XCTUnwrap(space ?? BrowserSession.preview.selectedSpace)
        let permissionCenter = center ?? BrowserSitePermissionCenter()
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
    var delaysAuthorization = false
    var authorizationContinuation: CheckedContinuation<BrowserGeolocationSystemAuthorization, Never>?

    init(authorization: BrowserGeolocationSystemAuthorization) {
        self.authorization = authorization
    }

    func currentAuthorization() -> BrowserGeolocationSystemAuthorization {
        authorization
    }

    func requestAuthorization() async -> BrowserGeolocationSystemAuthorization {
        if delaysAuthorization {
            return await withCheckedContinuation { authorizationContinuation = $0 }
        }
        return authorization
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

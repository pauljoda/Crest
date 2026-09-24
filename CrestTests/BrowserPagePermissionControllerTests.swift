import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPagePermissionControllerTests: XCTestCase {
    func testLocationAuthorizationRemembersAllowAndCannotOverrideANewerBlock() async throws {
        let controller = BrowserPagePermissionController()
        controller.setPresentationAvailable(true)
        let persistence = InMemoryBrowserSitePermissionPersistence()
        let center = BrowserSitePermissionCenter(persistence: persistence)
        let origin = BrowserSiteOrigin(scheme: "https", host: "location.example", port: 443)
        let spaceID = SpaceID()
        func authorize() async -> Bool {
            await controller.authorize(
                .location, origin: origin, topLevelOrigin: origin,
                spaceID: spaceID, spaceName: "Work", permissionCenter: center)
        }
        let first = Task { await authorize() }
        controller.resolve(try await pendingRequest(in: controller), response: .grantPersistently)
        let firstAllowed = await first.value
        XCTAssertTrue(firstAllowed)
        let remembered = await authorize()
        XCTAssertTrue(remembered)
        XCTAssertNil(controller.current)
        XCTAssertEqual(persistence.records.first?.decision, .grantPersistently)
        center.setDecision(.ask, for: .location, origin: origin, in: spaceID)
        let second = Task { await authorize() }
        let requestID = try await pendingRequest(in: controller)
        center.setDecision(.denyPersistently, for: .location, origin: origin, in: spaceID)
        controller.resolve(requestID, response: .grantPersistently)
        let secondAllowed = await second.value
        XCTAssertFalse(secondAllowed)
        XCTAssertEqual(persistence.records.first?.decision, .denyPersistently)
    }

    func testDownloadAndLocationDismissalAreTemporaryAndExplicitChoicesArePreserved() async throws {
        let controller = BrowserPagePermissionController()
        let origin = BrowserSiteOrigin(scheme: "https", host: "files.example", port: 443)
        for permission in [SitePermission.automaticDownloads, .location] {
            let unavailable = await controller.response(
                to: permission, origin: origin, topLevelOrigin: origin, spaceName: "Work")
            XCTAssertEqual(unavailable, .denyOnce)
            controller.setPresentationAvailable(true)
            for choice in [BrowserSitePermissionPromptResponse.grantPersistently, .denyPersistently] {
                let task = Task {
                    await controller.response(to: permission, origin: origin, topLevelOrigin: origin, spaceName: "Work")
                }
                controller.resolve(try await pendingRequest(in: controller), response: choice)
                let response = await task.value
                XCTAssertEqual(response, choice == .grantPersistently ? .grantPersistently : .denyPersistently)
            }
            let task = Task {
                await controller.response(to: permission, origin: origin, topLevelOrigin: origin, spaceName: "Work")
            }
            _ = try await pendingRequest(in: controller)
            controller.setPresentationAvailable(false)
            let dismissed = await task.value
            XCTAssertEqual(dismissed, .denyOnce)
        }
    }

    private func pendingRequest(in controller: BrowserPagePermissionController) async throws -> UUID {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while controller.current == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(controller.current?.id)
    }

    func testMediaRevocationStopsOnlyTheRevokedCapture() {
        let view = RecordingCaptureWebView()
        let center = BrowserSitePermissionCenter()
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "media.example", port: 443)
        center.setDecision(.grantPersistently, for: .camera, origin: origin, in: spaceID)
        center.setDecision(.grantPersistently, for: .microphone, origin: origin, in: spaceID)
        let session = BrowserPageSitePermissionSession(
            engine: BrowserWebKitPageEngine(webView: view), permissionCenter: center, spaceID: spaceID)
        session.recordMediaGrant(.camera, origin: origin)
        session.recordMediaGrant(.microphone, origin: origin)
        center.setDecision(.denyPersistently, for: .notifications, origin: origin, in: spaceID)
        center.setDecision(.ask, for: .camera, origin: origin, in: spaceID)
        XCTAssertEqual(view.cameraStops, 1)
        XCTAssertEqual(view.microphoneStops, 0)
    }

    func testDecisionChangedElsewhereReachesAnEngineThatEnforcesItAtOnce() {
        let engine = EnforcingPageEngine()
        let center = BrowserSitePermissionCenter()
        let spaceID = SpaceID()
        let page = URL(string: "https://maps.example/route")!
        let origin = BrowserSiteOrigin(scheme: "https", host: "maps.example", port: 443)
        let other = BrowserSiteOrigin(scheme: "https", host: "other.example", port: 443)
        let session = BrowserPageSitePermissionSession(engine: engine, permissionCenter: center, spaceID: spaceID)
        session.siteURL = { page }
        var refreshed: [SitePermission] = []
        session.siteDecisionDidChange = { refreshed.append($0) }

        center.setDecision(.grantPersistently, for: .location, origin: other, in: spaceID)
        center.setDecision(.grantPersistently, for: .location, origin: origin, in: SpaceID())
        XCTAssertTrue(engine.applied.isEmpty)

        center.setDecision(.denyPersistently, for: .location, origin: origin, in: spaceID)
        XCTAssertEqual(engine.applied.map(\.permission), [.location])
        XCTAssertEqual(engine.applied.map(\.allowed), [false])
        XCTAssertEqual(refreshed, [.location])
    }

    func testMediaDismissalDoesNotPersistAndAnOutstandingRequestCannotOverrideABlock() throws {
        let controller = BrowserPagePermissionController()
        controller.setPresentationAvailable(true)
        let center = BrowserSitePermissionCenter()
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "media.example", port: 443)
        var decisions: [WKPermissionDecision] = []
        SitePermission.camera.resolve(
            origin: origin, topLevelOrigin: origin, spaceID: spaceID, spaceName: "Work",
            permissionCenter: center, requests: controller
        ) { decisions.append($0) }
        controller.cancelAll()
        XCTAssertEqual(decisions, [.deny])
        XCTAssertEqual(center.mediaDecision(for: .camera, origin: origin, in: spaceID), .ask)
        SitePermission.camera.resolve(
            origin: origin, topLevelOrigin: origin, spaceID: spaceID, spaceName: "Work",
            permissionCenter: center, requests: controller
        ) { decisions.append($0) }
        let request = try XCTUnwrap(controller.current)
        center.setDecision(.denyPersistently, for: .camera, origin: origin, in: spaceID)
        controller.resolve(request.id, response: .grantPersistently)
        XCTAssertEqual(decisions, [.deny, .deny])
        XCTAssertEqual(center.mediaDecision(for: .camera, origin: origin, in: spaceID), .denyPersistently)
    }

    func testDismissalCancelsQueueWithoutSavingDenialsOrAnsweringLaterRequests() throws {
        let controller = BrowserPagePermissionController()
        controller.setPresentationAvailable(true)
        let origin = BrowserSiteOrigin(scheme: "https", host: "camera.example", port: 443)
        var responses: [BrowserSitePermissionPromptResponse?] = []
        for permission in [SitePermission.camera, .notifications] {
            controller.request(permission, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
                responses.append($0)
            }
        }
        let staleID = try XCTUnwrap(controller.current?.id)
        controller.cancelAll()
        XCTAssertEqual(responses.count, 2)
        XCTAssertTrue(responses.allSatisfy { $0 == nil })
        controller.request(.camera, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
            responses.append($0)
        }
        controller.resolve(staleID, response: .grantPersistently)
        XCTAssertEqual(responses.count, 2)
        controller.setPresentationAvailable(false)
        XCTAssertEqual(responses.count, 3)
        XCTAssertNil(responses.last!)
    }

    func testOriginsAndPermissionsRemainSeparateAndUnavailablePagesDenyTransiently() throws {
        let controller = BrowserPagePermissionController()
        let top = BrowserSiteOrigin(scheme: "https", host: "top.example", port: 443)
        let frame = BrowserSiteOrigin(scheme: "https", host: "frame.example", port: 443)
        var count = 0
        controller.request(.camera, origin: frame, topLevelOrigin: top, spaceName: "Work") {
            XCTAssertNil($0)
            count += 1
        }
        XCTAssertEqual(count, 1)
        XCTAssertNil(controller.current)
        controller.setPresentationAvailable(true)
        controller.request(.camera, origin: frame, topLevelOrigin: top, spaceName: "Work") { _ in }
        controller.request(.camera, origin: top, topLevelOrigin: top, spaceName: "Work") { _ in }
        let first = try XCTUnwrap(controller.current)
        XCTAssertEqual(first.origin, frame)
        controller.resolve(first.id, response: .denyPersistently)
        XCTAssertEqual(controller.current?.origin, top)
        controller.cancelAll()
    }
}

/// A page engine that enforces site permissions itself, as Chromium does.
@MainActor
private final class EnforcingPageEngine: BrowserPageEngine {
    var applied: [(permission: SitePermission, allowed: Bool?)] = []

    let registration = BrowserEngineRegistration.chromium
    let nativeView = NSView()
    var backHistory: [BrowserNavigationHistoryItem] { [] }
    var forwardHistory: [BrowserNavigationHistoryItem] { [] }
    var currentURL: URL? { nil }
    var canGoBack: Bool { false }
    var canGoForward: Bool { false }

    func applySitePermission(_ permission: SitePermission, allowed: Bool?) -> Bool {
        applied.append((permission, allowed))
        return true
    }

    func load(_ request: URLRequest) {}
    func navigateHistory(by offset: Int) {}
    func reload(bypassingCache: Bool) {}
    func stop() {}
    func mediaActivity() async -> BrowserPageMediaActivity? { nil }
    func transferOwnership(to windowID: BrowserWindowID) -> Bool { true }
    func capture(rect: CGRect?, width: CGFloat?, completion: @escaping @MainActor (NSImage?) -> Void) {
        completion(nil)
    }
    func setZoom(_ zoom: CGFloat) {}
    func performFind(
        _ query: String, configuration: BrowserFindConfiguration,
        completion: @escaping @MainActor (BrowserFindResult) -> Void
    ) {
        completion(.notFound)
    }
}

@MainActor
private final class RecordingCaptureWebView: WKWebView {
    var cameraStops = 0
    var microphoneStops = 0

    override func setCameraCaptureState(
        _ state: WKMediaCaptureState, completionHandler: (@MainActor @Sendable () -> Void)? = nil
    ) {
        if state == .none { cameraStops += 1 }
        completionHandler?()
    }

    override func setMicrophoneCaptureState(
        _ state: WKMediaCaptureState, completionHandler: (@MainActor @Sendable () -> Void)? = nil
    ) {
        if state == .none { microphoneStops += 1 }
        completionHandler?()
    }
}

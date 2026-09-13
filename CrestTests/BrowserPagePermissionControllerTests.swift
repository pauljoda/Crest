import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPagePermissionControllerTests: XCTestCase {
    func testMediaRevocationStopsOnlyTheRevokedCapture() async throws {
        let view = RecordingCaptureWebView()
        let center = BrowserSitePermissionCenter()
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "media.example", port: 443)
        center.setDecision(.grantPersistently, for: .camera, origin: origin, in: spaceID)
        center.setDecision(.grantPersistently, for: .microphone, origin: origin, in: spaceID)
        let session = BrowserMediaCaptureSession(webView: view, permissionCenter: center, spaceID: spaceID)
        session.recordGrant(.camera, origin: origin)
        session.recordGrant(.microphone, origin: origin)
        center.setDecision(.denyPersistently, for: .notifications, origin: origin, in: spaceID)
        center.setDecision(.ask, for: .camera, origin: origin, in: spaceID)
        let deadline = Date().addingTimeInterval(2)
        while view.cameraStops == 0 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(view.cameraStops, 1)
        XCTAssertEqual(view.microphoneStops, 0)
    }

    func testMediaDismissalDoesNotPersistAndAnOutstandingRequestCannotOverrideABlock() throws {
        let controller = BrowserPagePermissionController()
        controller.setPresentationAvailable(true)
        let center = BrowserSitePermissionCenter()
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "media.example", port: 443)
        var decisions: [WKPermissionDecision] = []
        BrowserMediaPermission.camera.resolve(
            origin: origin, topLevelOrigin: origin, spaceID: spaceID, spaceName: "Work",
            permissionCenter: center, requests: controller
        ) { decisions.append($0) }
        controller.cancelAll()
        XCTAssertEqual(decisions, [.deny])
        XCTAssertEqual(center.mediaDecision(for: .camera, origin: origin, in: spaceID), .ask)
        BrowserMediaPermission.camera.resolve(
            origin: origin, topLevelOrigin: origin, spaceID: spaceID, spaceName: "Work",
            permissionCenter: center, requests: controller
        ) { decisions.append($0) }
        let request = try XCTUnwrap(controller.current)
        center.setDecision(.denyPersistently, for: .camera, origin: origin, in: spaceID)
        controller.resolve(request.id, response: .grantPersistently)
        XCTAssertEqual(decisions, [.deny, .deny])
        XCTAssertEqual(center.mediaDecision(for: .camera, origin: origin, in: spaceID), .denyPersistently)
    }

    func testConcurrentRequestsCoalesceAndResolveExactlyOnce() throws {
        let controller = BrowserPagePermissionController()
        controller.setPresentationAvailable(true)
        let origin = BrowserSiteOrigin(scheme: "https", host: "camera.example", port: 443)
        var responses: [BrowserPagePermissionController.Response?] = []
        for _ in 0..<2 {
            controller.request(.camera, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
                responses.append($0)
            }
        }
        let request = try XCTUnwrap(controller.current)
        controller.resolve(request.id, response: .allowOnce)
        controller.resolve(request.id, response: .grantPersistently)
        XCTAssertEqual(responses, [.allowOnce, .allowOnce])
        XCTAssertNil(controller.current)
    }

    func testDismissalCancelsQueueWithoutSavingDenialsOrAnsweringLaterRequests() throws {
        let controller = BrowserPagePermissionController()
        controller.setPresentationAvailable(true)
        let origin = BrowserSiteOrigin(scheme: "https", host: "camera.example", port: 443)
        var responses: [BrowserPagePermissionController.Response?] = []
        for permission in [BrowserSitePermission.camera, .notifications] {
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

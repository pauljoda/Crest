import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserPagePermissionControllerTests: XCTestCase {
    func testMediaRevocationStopsOnlyTheRevokedCapture() {
        let pages = RecordingEnginePages()
        let center = BrowserSitePermissionCenter()
        let spaceID = UUID()
        let origin = SiteOrigin(scheme: "https", host: "media.example", port: 443)
        center.setDecision(.grantPersistently, for: .camera, origin: origin, in: spaceID)
        center.setDecision(.grantPersistently, for: .microphone, origin: origin, in: spaceID)
        let session = BrowserPageSitePermissionSession(
            page: pages.page(), permissionCenter: center, spaceID: spaceID)
        session.recordMediaGrant(.camera, origin: origin)
        session.recordMediaGrant(.microphone, origin: origin)
        center.setDecision(.denyPersistently, for: .notifications, origin: origin, in: spaceID)
        center.setDecision(.ask, for: .camera, origin: origin, in: spaceID)
        XCTAssertEqual(pages.stopped, [.camera])
    }

    func testDecisionChangedElsewhereReachesAnEngineThatEnforcesItAtOnce() {
        let pages = RecordingEnginePages()
        let center = BrowserSitePermissionCenter()
        let spaceID = UUID()
        let page = URL(string: "https://maps.example/route")!
        let origin = SiteOrigin(scheme: "https", host: "maps.example", port: 443)
        let other = SiteOrigin(scheme: "https", host: "other.example", port: 443)
        let session = BrowserPageSitePermissionSession(page: pages.page(), permissionCenter: center, spaceID: spaceID)
        session.siteURL = { page }
        var refreshed: [SitePermission] = []
        session.siteDecisionDidChange = { refreshed.append($0) }

        center.setDecision(.grantPersistently, for: .location, origin: other, in: spaceID)
        center.setDecision(.grantPersistently, for: .location, origin: origin, in: UUID())
        XCTAssertTrue(pages.applied.isEmpty)

        center.setDecision(.denyPersistently, for: .location, origin: origin, in: spaceID)
        XCTAssertEqual(pages.applied.map(\.permission), [.location])
        XCTAssertEqual(pages.applied.map(\.allowed), [false])
        XCTAssertEqual(refreshed, [.location])
    }

    /// A page opened from a Quick Window gains the main window's host before
    /// the Quick Window's host leaves; its request must still be shown, and
    /// it ends only once no window can show it.
    func testRequestSurvivesTheOldHostLeavingAfterTheNewOneAttached() {
        let controller = BrowserPagePermissionController()
        let origin = SiteOrigin(scheme: "https", host: "meet.example", port: 443)
        let quickWindow = UUID()
        let mainWindow = UUID()
        var answers: [BrowserSitePermissionPromptResponse?] = []

        controller.request(.microphone, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
            answers.append($0)
        }
        XCTAssertEqual(answers.count, 1, "A page no window shows cannot ask.")
        XCTAssertNil(answers[0])

        controller.attachHost(quickWindow)
        controller.request(.microphone, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
            answers.append($0)
        }
        controller.attachHost(mainWindow)
        controller.detachHost(quickWindow)
        XCTAssertNotNil(controller.current)
        XCTAssertEqual(answers.count, 1)

        controller.detachHost(mainWindow)
        drainMainQueue()
        XCTAssertNil(controller.current)
        XCTAssertEqual(answers.count, 2)
        XCTAssertNil(answers[1])
    }

    /// The Quick Window's host can leave before the main window's arrives;
    /// a host arriving within the same main turn keeps the request.
    func testRequestSurvivesTheOldHostLeavingBeforeTheNewOneAttached() {
        let controller = BrowserPagePermissionController()
        let origin = SiteOrigin(scheme: "https", host: "meet.example", port: 443)
        let quickWindow = UUID()
        let mainWindow = UUID()
        var answers: [BrowserSitePermissionPromptResponse?] = []

        controller.attachHost(quickWindow)
        controller.request(.camera, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
            answers.append($0)
        }
        controller.detachHost(quickWindow)
        controller.attachHost(mainWindow)
        drainMainQueue()
        XCTAssertNotNil(controller.current)
        XCTAssertTrue(answers.isEmpty)
    }

    /// Lets work the controller deferred to the next main turn run.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    /// Answering the first of two queued requests answers only it; the next
    /// one waits for its own answer.
    func testAnsweringOneRequestLeavesTheNextPending() {
        let controller = BrowserPagePermissionController()
        let origin = SiteOrigin(scheme: "https", host: "meet.example", port: 443)
        controller.attachHost(UUID())
        var microphone: [BrowserSitePermissionPromptResponse?] = []
        var camera: [BrowserSitePermissionPromptResponse?] = []
        controller.request(.microphone, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
            microphone.append($0)
        }
        controller.request(.camera, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
            camera.append($0)
        }

        let first = controller.current
        XCTAssertEqual(first?.permission, .microphone)
        controller.resolve(first!.id, response: .allowOnce)

        XCTAssertEqual(microphone.count, 1)
        XCTAssertEqual(microphone.first??.grants, true)
        XCTAssertEqual(controller.current?.permission, .camera)
        XCTAssertTrue(camera.isEmpty)
    }
}

/// An engine's direct path that records the site decisions carried to it.
@MainActor
private final class RecordingEnginePages: EnginePages {
    private(set) var applied: [(permission: SitePermission, allowed: Bool?)] = []
    private(set) var stopped: [SitePermission] = []

    /// A page over this path.
    func page() -> EnginePage {
        EnginePage(id: UUID(), pages: self, historyFamily: .chromium, historyVersion: { nil }, inspectorPanels: [])
    }

    func attach(_ page: EnginePage) {}

    func request<Request: PageRequest>(_ request: Request) -> Request.Answer {
        switch request {
        case let setting as SetSitePermission: applied.append((setting.permission, setting.allowed))
        case let stopping as StopMediaCapture: stopped.append(stopping.permission)
        default: XCTFail("The session asked for \(Request.self).")
        }
        guard let answer = true as? Request.Answer else { preconditionFailure("A site request answers Bool.") }
        return answer
    }
}

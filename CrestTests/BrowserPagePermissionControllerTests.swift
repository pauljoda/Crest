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

    /// A page no window shows waits for one only as long as the grace: a
    /// Quick Window's page asking during its first load is shown once the
    /// window draws, and a page nobody shows ends its request unanswered.
    func testARequestWaitsForAWindowOnlyAsLongAsTheGrace() {
        let controller = BrowserPagePermissionController(hostGrace: .milliseconds(100))
        let origin = SiteOrigin(scheme: "https", host: "meet.example", port: 443)
        var answers: [BrowserSitePermissionPromptResponse?] = []

        controller.request(.camera, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
            answers.append($0)
        }
        let quickWindow = UUID()
        controller.attachHost(quickWindow)
        waitPast(.milliseconds(150))
        XCTAssertEqual(controller.current?.permission, .camera)
        XCTAssertTrue(answers.isEmpty)

        controller.detachHost(quickWindow)
        waitPast(.milliseconds(150))
        XCTAssertNil(controller.current)
        XCTAssertEqual(answers.count, 1)
        XCTAssertNil(answers[0])
    }

    /// A page moving from a Quick Window into a browser window keeps its
    /// request whichever window's view arrives first: the new one before the
    /// old one leaves, or a moment after it.
    func testARequestSurvivesItsPageChangingWindows() {
        let controller = BrowserPagePermissionController(hostGrace: .milliseconds(100))
        let origin = SiteOrigin(scheme: "https", host: "meet.example", port: 443)
        let (quickWindow, mainWindow, otherWindow) = (UUID(), UUID(), UUID())
        var answers: [BrowserSitePermissionPromptResponse?] = []

        controller.attachHost(quickWindow)
        controller.request(.microphone, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
            answers.append($0)
        }
        controller.attachHost(mainWindow)
        controller.detachHost(quickWindow)
        controller.detachHost(mainWindow)
        controller.attachHost(otherWindow)
        waitPast(.milliseconds(150))
        XCTAssertEqual(controller.current?.permission, .microphone)
        XCTAssertTrue(answers.isEmpty)
    }

    /// Lets the controller's grace pass on the main actor.
    private func waitPast(_ duration: Duration) {
        let passed = expectation(description: "grace passed")
        Task { @MainActor in
            try? await Task.sleep(for: duration)
            passed.fulfill()
        }
        wait(for: [passed], timeout: 5)
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

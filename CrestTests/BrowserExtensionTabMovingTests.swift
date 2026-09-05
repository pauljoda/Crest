import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionTabMovingTests: XCTestCase {
    func testBrokerRequiresVerifiedContextAndRejectsStaleTargetsBeforeMoving() async throws {
        let browser = BrowserStore(session: makeSession(), persistence: InMemoryBrowserSessionPersistence())
        let space = browser.session.spaces[0]
        let coordinator = BrowserExtensionTabWindowCoordinator()
        coordinator.browser = browser
        coordinator.reconcileCurrentSession()
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        coordinator.register(controller: controller, spaceID: space.id)
        defer { coordinator.unregister(spaceID: space.id) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/DebuggerAgentProbeExtension", directoryHint: .isDirectory)
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: fixture))
        try controller.load(context)
        defer { try? controller.unload(context) }
        var failure: (any Error)?
        func send(_ tabs: [[String: Any]]) {
            failure = nil
            XCTAssertTrue(
                coordinator.handleCapabilityBrokerTabMove(
                    ["api": "tabs.move", "tabs": tabs, "index": 0],
                    applicationIdentifier: BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
                    controller: controller, extensionContext: context,
                    replyHandler: { _, error in failure = error }))
        }
        send([["tabIndex": 3]])
        XCTAssertNotNil(failure)
        coordinator.registerCapabilityBrokerAuthorization(.init(allowsInternalCapabilityBroker: true), for: context)
        send([["tabIndex": 3], ["tabIndex": 2, "url": "https://different.example/"]])
        XCTAssertNotNil(failure)
        XCTAssertEqual(browser.session.spaces[0].tabs.map(\.id), space.tabs.map(\.id))
        send([["tabIndex": 3]])
        XCTAssertNil(failure)
        XCTAssertEqual(browser.session.spaces[0].tabs.first?.id, space.tabs[3].id)
        XCTAssertEqual(coordinator.lastState?.space(space.id)?.tabs.first?.id, space.tabs[3].id)
    }

    func testSingletonFolderKeepsItsIdentityWhenMoved() throws {
        var session = makeSession()
        let spaceID = session.spaces[0].id
        let tabID = session.spaces[0].tabs[0].id
        let folderID = try XCTUnwrap(session.createTabFolder([tabID], in: spaceID, title: "Research"))
        XCTAssertTrue(session.moveExtensionTabs([tabID], in: spaceID, to: -1))
        XCTAssertEqual(session.spaces[0].tabs.last?.id, tabID)
        XCTAssertEqual(session.spaces[0].tabs.last?.folderID, folderID)
        XCTAssertEqual(session.spaces[0].folders.first?.title, "Research")
    }

    func testReorderWithinFolderAndMoveIntoAndOutOfItPreservesSelection() throws {
        var session = makeSession()
        let spaceID = session.spaces[0].id
        let ids = session.spaces[0].tabs.map(\.id)
        let folder = try XCTUnwrap(session.createTabFolder(Array(ids.prefix(2)), in: spaceID))
        let selected = session.spaces[0].selectedTabID
        XCTAssertTrue(session.moveExtensionTabs([ids[1]], in: spaceID, to: 0))
        XCTAssertEqual(session.spaces[0].tabs.map(\.id), [ids[1], ids[0], ids[2], ids[3]])
        XCTAssertEqual(session.spaces[0].tabs[0].folderID, folder)
        XCTAssertTrue(session.moveExtensionTabs([ids[2]], in: spaceID, to: 1))
        XCTAssertEqual(session.spaces[0].tabs[1].folderID, folder)
        XCTAssertTrue(session.moveExtensionTabs([ids[2]], in: spaceID, to: -1))
        XCTAssertEqual(session.spaces[0].tabs.last?.id, ids[2])
        XCTAssertNil(session.spaces[0].tabs.last?.folderID)
        XCTAssertEqual(session.spaces[0].selectedTabID, selected)
    }

    func testMultipleMovesKeepRequestOrderAndInvalidTargetsDoNotPartiallyMove() {
        var session = makeSession()
        let spaceID = session.spaces[0].id
        let ids = session.spaces[0].tabs.map(\.id)
        XCTAssertTrue(session.moveExtensionTabs([ids[3], ids[2]], in: spaceID, to: 0))
        XCTAssertEqual(session.spaces[0].tabs.map(\.id), [ids[3], ids[2], ids[0], ids[1]])
        let before = session
        XCTAssertFalse(session.moveExtensionTabs([ids[0], TabID()], in: spaceID, to: 0))
        XCTAssertFalse(session.moveExtensionTabs([ids[0]], in: spaceID, to: -2))
        XCTAssertEqual(session, before)
    }

    func testPinnedMovesStayPinnedAndBackgroundSpaceDoesNotBecomeSelected() {
        var session = makeSession()
        let spaceID = session.spaces[0].id
        let ids = session.spaces[0].tabs.map(\.id)
        _ = session.setExtensionTabPinned(true, tabID: ids[0], in: spaceID)
        _ = session.setExtensionTabPinned(true, tabID: ids[1], in: spaceID)
        let second = BrowserSession.makeBlankSpace(number: 2)
        session.spaces.append(second)
        session.selectedSpaceID = second.id
        XCTAssertTrue(session.moveExtensionTabs([ids[0]], in: spaceID, to: 999))
        XCTAssertEqual(session.spaces[0].tabs.prefix(2).map(\.id), [ids[1], ids[0]])
        XCTAssertEqual(session.spaces[0].tabs[1].placement, .pinned)
        XCTAssertTrue(session.moveExtensionTabs([ids[3]], in: spaceID, to: 0))
        XCTAssertEqual(session.spaces[0].tabs[2].id, ids[3])
        XCTAssertEqual(session.selectedSpaceID, second.id)
    }

    private func makeSession() -> BrowserSession {
        var space = BrowserSession.makeBlankSpace(number: 1)
        space.tabs = (0..<4).map {
            BrowserTab(title: "Page \($0)", url: URL(string: "https://example.org/\($0)"), placement: .current)
        }
        space.selectedTabID = space.tabs[0].id
        return .init(spaces: [space], selectedSpaceID: space.id)
    }
}

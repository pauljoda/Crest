import Foundation
import XCTest

@testable import Crest

final class BrowserExtensionSidebarBrokerRequestTests: XCTestCase {
    func testOptionsPreserveOmittedFieldsAndResolveOnlySessionTabs() throws {
        let tab = BrowserTab(title: "Page", url: URL(string: "https://example.com/"), placement: .current)
        var space = BrowserSession.preview.spaces[0]
        space.tabs = [tab]
        let state = BrowserExtensionSessionState(session: .init(spaces: [space], selectedSpaceID: space.id))
        let request = try BrowserExtensionSidebarBrokerRequest(message: [
            "api": "sidePanel.setOptions", "enabled": false,
            "scope": ["kind": "tab", "windowKind": "primary", "tabIndex": 0, "url": "https://example.com/"],
        ])
        XCTAssertNil(request.path)
        XCTAssertEqual(request.enabled, false)
        XCTAssertEqual(try request.resolveScope(in: state.space(space.id)!, liveTabs: [tab.id]), .tab(tab.id))
        XCTAssertThrowsError(try request.resolveScope(in: state.space(space.id)!, liveTabs: []))
    }

    func testStaleIndexCannotTargetADifferentURL() throws {
        let tab = BrowserExtensionTabState(
            id: TabID(), title: "Changed", url: URL(string: "https://new.example/"),
            placement: .current, index: 0, isSelected: true)
        let request = try BrowserExtensionSidebarBrokerRequest(message: [
            "api": "sidePanel.open", "windowKind": "primary", "tabIndex": 0, "url": "https://old.example/",
            "userActivation": true,
        ])
        XCTAssertTrue(request.userActivation)
        XCTAssertThrowsError(try request.resolveScope(in: .init(id: SpaceID(), tabs: [tab]), liveTabs: [tab.id]))
    }

    func testFirefoxNullClearsTitleAndPanelWhileMissingValuesReject() throws {
        let title = try BrowserExtensionSidebarBrokerRequest(message: [
            "api": "sidebarAction.setTitle", "scope": ["kind": "default"], "title": NSNull(),
        ])
        XCTAssertTrue(title.clearsTitle)
        let panel = try BrowserExtensionSidebarBrokerRequest(message: [
            "api": "sidebarAction.setPanel", "scope": ["kind": "default"], "panel": NSNull(),
        ])
        XCTAssertEqual(panel.path, "")
        XCTAssertThrowsError(
            try BrowserExtensionSidebarBrokerRequest(message: [
                "api": "sidebarAction.setPanel", "scope": ["kind": "default"],
            ]))
    }

    func testRejectsUnknownAndMalformedTargetsAndImageData() {
        for payload: [String: Any] in [
            ["api": "sidebarAction.setBadgeText"],
            ["api": "sidePanel.open"],
            ["api": "sidePanel.open", "windowKind": "auxiliary"],
            ["api": "sidePanel.getOptions", "scope": ["kind": "tab", "windowKind": "primary", "tabIndex": -1]],
            ["api": "sidePanel.setOptions", "scope": ["kind": "default"], "path": NSNull()],
            ["api": "sidebarAction.setIcon", "scope": ["kind": "default"], "imageData": [:]],
        ] {
            XCTAssertThrowsError(try BrowserExtensionSidebarBrokerRequest(message: payload), "\(payload)")
        }
    }

    func testBehaviorOmissionIsAnUpsertAndEveryOperationHasAnExplicitGrant() throws {
        let behavior = try BrowserExtensionSidebarBrokerRequest(message: ["api": "sidePanel.setPanelBehavior"])
        XCTAssertNil(behavior.openPanelOnActionClick)
        XCTAssertEqual(behavior.requiredCapability, "sidePanel")
        let firefox = try BrowserExtensionSidebarBrokerRequest(message: [
            "api": "sidebarAction.close", "windowKind": "primary",
        ])
        XCTAssertEqual(firefox.requiredCapability, "sidebarAction")
        XCTAssertTrue(firefox.requiresUserGesture)
    }
}

final class BrowserExtensionUserGestureLedgerTests: XCTestCase {
    func testGesturesAreClientScopedExpireAndCannotComeFromTheFuture() throws {
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("first"))
        let other = try XCTUnwrap(BrowserExtensionServiceClientID("second"))
        var ledger = BrowserExtensionUserGestureLedger()
        XCTAssertFalse(ledger.hasRecentGesture(for: client, now: 100))
        ledger.note(for: client, now: 100)
        XCTAssertTrue(ledger.hasRecentGesture(for: client, now: 104.9))
        XCTAssertFalse(ledger.hasRecentGesture(for: other, now: 101))
        XCTAssertFalse(ledger.hasRecentGesture(for: client, now: 99))
        XCTAssertFalse(ledger.hasRecentGesture(for: client, now: 105.1))
        ledger.remove(client: client)
        XCTAssertFalse(ledger.hasRecentGesture(for: client, now: 101))
    }
}

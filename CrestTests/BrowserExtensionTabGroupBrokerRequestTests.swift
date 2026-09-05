import Foundation
import XCTest

@testable import Crest

final class BrowserExtensionTabGroupBrokerRequestTests: XCTestCase {
    func testEveryOperationDeclaresTheGrantChromeGatesItWith() throws {
        for api in ["tabGroups.get", "tabGroups.update", "tabGroups.move"] {
            let request = try BrowserExtensionTabGroupBrokerRequest(message: ["api": api, "groupId": 3, "index": -1])
            XCTAssertEqual(request.requiredCapability, "tabGroups", api)
            XCTAssertEqual(request.groupID, 3, api)
        }
        XCTAssertEqual(
            try BrowserExtensionTabGroupBrokerRequest(message: ["api": "tabGroups.query"])
                .requiredCapability, "tabGroups")
        // Ordinary tab metadata and grouping require no sensitive-tab grant.
        for api in ["tabs.group", "tabs.ungroup"] {
            let request = try BrowserExtensionTabGroupBrokerRequest(message: [
                "api": api, "tabs": [["tabIndex": 0]],
            ])
            XCTAssertNil(request.requiredCapability, api)
        }
        XCTAssertNil(
            try BrowserExtensionTabGroupBrokerRequest(message: ["api": "tabGroups.membership"])
                .requiredCapability)
    }

    func testTabTargetsAreReverifiedAgainstTheLiveSpace() throws {
        let tab = BrowserTab(title: "Page", url: URL(string: "https://example.com/"), placement: .current)
        var space = BrowserSession.preview.spaces[0]
        space.tabs = [tab]
        let state = BrowserExtensionSessionState(
            session: .init(spaces: [space], selectedSpaceID: space.id))
        let live = try XCTUnwrap(state.space(space.id))
        let request = try BrowserExtensionTabGroupBrokerRequest(message: [
            "api": "tabs.group", "tabs": [["tabIndex": 0, "url": "https://example.com/"]],
        ])

        XCTAssertEqual(try request.resolveTabs(in: live, liveTabs: [tab.id]), [tab.id])
        // A transient page — a Peek — is announced to extensions but excluded
        // from `liveTabs`, so it can never be grouped.
        XCTAssertThrowsError(try request.resolveTabs(in: live, liveTabs: []))

        let moved = try BrowserExtensionTabGroupBrokerRequest(message: [
            "api": "tabs.ungroup", "tabs": [["tabIndex": 0, "url": "https://other.example/"]],
        ])
        XCTAssertThrowsError(try moved.resolveTabs(in: live, liveTabs: [tab.id])) { error in
            XCTAssertEqual(error as? BrowserExtensionTabGroupBrokerError, .staleTab)
        }
    }

    func testMalformedRequestsAreRejectedBeforeReachingTheRegistry() {
        for payload: [String: Any] in [
            ["api": "tabGroups.rename", "groupId": 1],
            ["api": "tabGroups.get"],
            ["api": "tabGroups.get", "groupId": "1"],
            ["api": "tabGroups.get", "groupId": true],
            ["api": "tabGroups.get", "groupId": 1.5],
            ["api": "tabGroups.update", "groupId": 1, "color": "chartreuse"],
            ["api": "tabGroups.query", "collapsed": 1],
            ["api": "tabs.group", "tabs": []],
            ["api": "tabs.group", "tabs": [["tabIndex": -1]]],
            ["api": "tabs.ungroup", "tabs": [["url": "https://example.com/"]]],
        ] {
            XCTAssertThrowsError(
                try BrowserExtensionTabGroupBrokerRequest(message: payload), "\(payload)")
        }
    }

    func testChromeErrorTextIsReproducedVerbatim() {
        XCTAssertEqual(
            BrowserExtensionTabGroupBrokerError.unknownGroup(7).errorDescription,
            "No group with id: 7.")
        XCTAssertEqual(
            BrowserExtensionTabGroupBrokerError.failedToMove.errorDescription,
            "Failed to move group.")
        XCTAssertEqual(
            BrowserExtensionTabGroupBrokerError.staleTab.errorDescription, "Unable to find tab.")
    }

    func testQueryFilterMatchesChromiumGlobTitlesAndNeverReportsSharedGroups() throws {
        let request = try BrowserExtensionTabGroupBrokerRequest(message: [
            "api": "tabGroups.query", "title": "Res*ch", "color": "orange", "collapsed": true,
        ])
        var group = BrowserExtensionTabGroup(
            id: .init(rawValue: 1), spaceID: SpaceID(), tabs: [TabID()], title: "Research",
            color: .orange, isCollapsed: true)
        XCTAssertTrue(request.filter.matches(group))

        // `*` spans any run, including an empty one.
        group.title = "Resch"
        XCTAssertTrue(request.filter.matches(group))
        group.title = "Reach"
        XCTAssertFalse(request.filter.matches(group))
        group.title = "Research"
        group.color = .blue
        XCTAssertFalse(request.filter.matches(group))

        // Crest has no group-sharing feature, so `shared: true` matches
        // nothing rather than being silently ignored.
        let shared = try BrowserExtensionTabGroupBrokerRequest(message: [
            "api": "tabGroups.query", "shared": true,
        ])
        XCTAssertFalse(shared.filter.matches(group))
        let unshared = try BrowserExtensionTabGroupBrokerRequest(message: [
            "api": "tabGroups.query", "shared": false,
        ])
        XCTAssertTrue(unshared.filter.matches(group))
    }

    func testTitlePatternFollowsBaseMatchPattern() {
        XCTAssertTrue(BrowserExtensionTabGroupTitlePattern.matches("Research", pattern: "*"))
        XCTAssertTrue(BrowserExtensionTabGroupTitlePattern.matches("", pattern: "*"))
        XCTAssertTrue(BrowserExtensionTabGroupTitlePattern.matches("abc", pattern: "a?c"))
        XCTAssertFalse(BrowserExtensionTabGroupTitlePattern.matches("ac", pattern: "a?c"))
        XCTAssertTrue(BrowserExtensionTabGroupTitlePattern.matches("aXbXc", pattern: "a*b*c"))
        XCTAssertFalse(BrowserExtensionTabGroupTitlePattern.matches("aXbX", pattern: "a*b*c"))
        XCTAssertTrue(BrowserExtensionTabGroupTitlePattern.matches("abab", pattern: "*ab"))
        XCTAssertFalse(BrowserExtensionTabGroupTitlePattern.matches("Research", pattern: "research"))
        // A glob, not a regular expression: `.` is a literal.
        XCTAssertFalse(BrowserExtensionTabGroupTitlePattern.matches("ab", pattern: "a.b"))
    }
}

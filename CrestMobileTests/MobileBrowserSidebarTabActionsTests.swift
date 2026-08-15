import Foundation
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserSidebarTabActionsTests: XCTestCase {
    func testFaviconPullCannotWriteAfterProfileReplacementDuringAwait() async throws {
        let context = makeContext()
        let expectedData = Data("replacement-race".utf8)
        let action = MobileBrowserSidebarTabActions(
            assignment: context.assignment,
            browser: context.browser,
            spaceAccess: context.access
        ) { _, _ in
            context.browser.session.spaces[0] = self.replacingProfile(
                in: context.space
            )
            return (expectedData, nil)
        }

        let didPullIcon = await action.pullNewIcon(for: context.tab.id)
        XCTAssertFalse(didPullIcon)
        XCTAssertNil(
            try XCTUnwrap(context.browser.session.space(id: context.space.id))
                .tabs.first(where: { $0.id == context.tab.id })?
                .faviconData
        )
    }

    func testFaviconPullCannotWriteAfterProtectedSpaceRelocksDuringAwait() async throws {
        let context = makeContext(isProtected: true)
        let didUnlockSpace = await context.access.unlock(context.space)
        XCTAssertTrue(didUnlockSpace)
        let action = MobileBrowserSidebarTabActions(
            assignment: context.assignment,
            browser: context.browser,
            spaceAccess: context.access
        ) { _, _ in
            context.access.lock(context.space.id)
            return (Data("relocked".utf8), nil)
        }

        let didPullIcon = await action.pullNewIcon(for: context.tab.id)
        XCTAssertFalse(didPullIcon)
        XCTAssertNil(
            try XCTUnwrap(context.browser.selectedSpace)
                .tabs.first(where: { $0.id == context.tab.id })?
                .faviconData
        )
    }

    func testExactAssignmentAcceptsPulledFavicon() async throws {
        let context = makeContext()
        let expectedData = Data("exact-favicon".utf8)
        let expectedAccent = BrowserTabIconAccent(
            red: 0.2,
            green: 0.4,
            blue: 0.6
        )
        let action = MobileBrowserSidebarTabActions(
            assignment: context.assignment,
            browser: context.browser,
            spaceAccess: context.access
        ) { _, _ in
            (expectedData, expectedAccent)
        }

        let didPullIcon = await action.pullNewIcon(for: context.tab.id)
        XCTAssertTrue(didPullIcon)
        let tab = try XCTUnwrap(
            context.browser.selectedSpace?.tabs.first(where: {
                $0.id == context.tab.id
            })
        )
        XCTAssertEqual(tab.faviconData, expectedData)
        XCTAssertEqual(tab.iconAccent, expectedAccent)
    }

    private func makeContext(isProtected: Bool = false) -> Context {
        let tab = BrowserTab(
            id: TabID(rawValue: Self.uuid(1)),
            title: "Exact tab",
            url: URL(string: "https://sidebar.crest.test"),
            placement: .saved
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(2)),
            profile: BrowsingProfile(id: Self.uuid(3)),
            name: "Exact Space",
            symbol: "sidebar.left",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open,
            selectedTabID: tab.id
        )
        return Context(
            browser: BrowserStore(
                session: BrowserSession(
                    spaces: [space],
                    selectedSpaceID: space.id
                ),
                persistence: InMemoryBrowserSessionPersistence(),
                browsingMode: .privateBrowsing
            ),
            access: BrowserSpaceAccessController(
                authenticator: AcceptingAuthenticator()
            ),
            space: space,
            tab: tab
        )
    }

    private func replacingProfile(in space: BrowserSpace) -> BrowserSpace {
        BrowserSpace(
            id: space.id,
            profile: BrowsingProfile(id: Self.uuid(4)),
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            branding: space.branding,
            folders: space.folders,
            tabs: space.tabs,
            archivedTabs: space.archivedTabs,
            history: space.history,
            browsingPreferences: space.browsingPreferences,
            credentialPreferences: space.credentialPreferences,
            accessPolicy: space.accessPolicy,
            isSavedTabsExpanded: space.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: space.savedTabsExpansionModifiedAt,
            selectedTabID: space.selectedTabID
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x49,
                0x43, 0x4F, 0x4E, 0x53, 0x00, 0x00, 0x00, finalByte
            )
        )
    }

    private struct Context {
        let browser: BrowserStore
        let access: BrowserSpaceAccessController
        let space: BrowserSpace
        let tab: BrowserTab

        var assignment: BrowserSpaceRuntimeAssignment {
            BrowserSpaceRuntimeAssignment(space: space)
        }
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}

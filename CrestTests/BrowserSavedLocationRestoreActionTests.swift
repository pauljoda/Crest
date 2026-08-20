import XCTest

@testable import Crest

@MainActor
final class BrowserSavedLocationRestoreActionTests: XCTestCase {
    func testStaleSavedLocationActionCannotNavigateTheSelectedSpace() throws {
        let savedURL = try XCTUnwrap(URL(string: "https://example.com/saved"))
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/current"))
        let sourceTab = BrowserTab(
            id: TabID(
                rawValue: UUID(
                    uuid: (
                        0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x41,
                        0x43, 0x54, 0x49, 0x4F, 0x4E, 0x00, 0x00, 0x01
                    )
                )
            ),
            title: "Source",
            url: currentURL,
            savedURL: savedURL,
            placement: .pinned
        )
        let source = BrowserSpace(
            id: SpaceID(
                rawValue: UUID(
                    uuid: (
                        0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x41,
                        0x43, 0x54, 0x49, 0x4F, 0x4E, 0x00, 0x00, 0x02
                    )
                )
            ),
            profile: BrowsingProfile(
                id: UUID(
                    uuid: (
                        0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x41,
                        0x43, 0x54, 0x49, 0x4F, 0x4E, 0x00, 0x00, 0x03
                    )
                )
            ),
            name: "Source",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab],
            selectedTabID: sourceTab.id
        )
        let destinationTab = BrowserTab.startPage(
            id: TabID(
                rawValue: UUID(
                    uuid: (
                        0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x41,
                        0x43, 0x54, 0x49, 0x4F, 0x4E, 0x00, 0x00, 0x04
                    )
                )
            ),
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let destination = BrowserSpace(
            id: SpaceID(
                rawValue: UUID(
                    uuid: (
                        0x53, 0x49, 0x45, 0x45, 0x42, 0x41, 0x52, 0x41,
                        0x43, 0x54, 0x49, 0x4F, 0x4E, 0x00, 0x00, 0x05
                    )
                )
            ),
            profile: BrowsingProfile(
                id: UUID(
                    uuid: (
                        0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x41,
                        0x43, 0x54, 0x49, 0x4F, 0x4E, 0x00, 0x00, 0x06
                    )
                )
            ),
            name: "Destination",
            symbol: "house.fill",
            accent: .orange,
            folders: [],
            tabs: [destinationTab],
            selectedTabID: destinationTab.id
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [source, destination],
                selectedSpaceID: destination.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true,
            extensionControllerPool: BrowserExtensionControllerPool(),
            permissionCenter: BrowserSitePermissionCenter()
        )
        let action = BrowserSavedLocationRestoreAction(
            browser: browser,
            pages: pages,
            spaceAccess: BrowserSpaceAccessController(
                authenticator: BrowserPreviewAuthenticator(result: true)
            )
        )

        XCTAssertFalse(
            action.perform(
                BrowserTabRuntimeAssignment(
                    tabID: sourceTab.id,
                    spaceID: source.id,
                    profileID: source.profile.id
                )
            )
        )

        XCTAssertEqual(
            browser.session.space(id: source.id)?.tabs.first?.url,
            currentURL
        )
        XCTAssertEqual(browser.session.selectedSpaceID, destination.id)
        XCTAssertEqual(browser.selectedTab?.id, destinationTab.id)
        XCTAssertNil(pages.activePage)
    }
}

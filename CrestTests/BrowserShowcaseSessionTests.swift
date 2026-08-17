import XCTest

@testable import Crest

final class BrowserShowcaseSessionTests: XCTestCase {
    func testShowcaseSessionIsSafeRichTwoSpaceShowcase() throws {
        let session = BrowserSession.showcase

        XCTAssertEqual(session.spaces.map(\.name), ["Work", "Personal"])
        XCTAssertEqual(Set(session.spaces.map(\.profile.id)).count, 2)

        for space in session.spaces {
            XCTAssertEqual(space.branding.colors.count, 3)
            XCTAssertEqual(space.branding.iconStyle, .layeredCrest)
            XCTAssertTrue(space.branding.showsTexture)
            XCTAssertFalse(space.pinnedTabs.isEmpty)

            let selectedTab = try XCTUnwrap(
                space.tabs.first { $0.id == space.selectedTabID }
            )
            XCTAssertEqual(selectedTab.url?.scheme, "data")
        }

        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)
        XCTAssertEqual(
            Set(work.archivedTabs.map(\.reason)),
            [.synced, .closed, .autoCleanup]
        )
        XCTAssertNotEqual(work.branding.bannerPattern, personal.branding.bannerPattern)
        XCTAssertNotEqual(work.branding.crest.symbol, personal.branding.crest.symbol)
        XCTAssertTrue(
            session.spaces
                .flatMap(\.tabs)
                .compactMap(\.url)
                .allSatisfy { $0.scheme == "data" }
        )
    }

    func testShowcaseDownloadLedgerIncludesFinishedAndActiveNotifications() throws {
        let profileID = UUID()
        let ledger = BrowserDownloadLedger.showcase(profileID: profileID)
        let items = ledger.items(for: profileID)
        let finishedItem = try XCTUnwrap(items.first { $0.state == .finished })
        let activeItem = try XCTUnwrap(items.first { $0.state == .downloading })

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(ledger.unacknowledgedItems(for: profileID).count, 2)
        XCTAssertEqual(activeItem.progress, 0.64, accuracy: 0.001)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(finishedItem.destinationURL).path
            )
        )
    }

    @MainActor
    func testShowcaseLaunchUsesTheShowcaseWithoutChangingPreviewFixtures() throws {
        let store = BrowserStore.isolatedLaunch(
            launchEnvironment: BrowserLaunchEnvironment(
                values: ["CREST_SHOWCASE_SESSION": "1"],
                isXCTestRuntime: false
            )
        )
        let names = store.session.spaces.map(\.name)
        let selectedSpace = try XCTUnwrap(store.session.selectedSpace)
        let selectedTab = try XCTUnwrap(
            selectedSpace.tabs.first { $0.id == selectedSpace.selectedTabID }
        )
        let previewSpace = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        let previewTab = try XCTUnwrap(
            previewSpace.tabs.first { $0.id == previewSpace.selectedTabID }
        )

        XCTAssertEqual(names, ["Work", "Personal"])
        XCTAssertEqual(selectedTab.url?.scheme, "data")
        XCTAssertNil(previewTab.url)
    }

    @MainActor
    func testResetLaunchKeepsTheStablePreviewSession() {
        let store = BrowserStore.isolatedLaunch(
            launchEnvironment: BrowserLaunchEnvironment(
                values: ["CREST_RESET_SESSION": "1"],
                isXCTestRuntime: false
            )
        )

        XCTAssertEqual(
            store.session.spaces.map(\.name),
            BrowserSession.preview.spaces.map(\.name)
        )
    }
}

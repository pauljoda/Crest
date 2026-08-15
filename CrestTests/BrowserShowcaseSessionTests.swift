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
        XCTAssertNotEqual(work.branding.bannerPattern, personal.branding.bannerPattern)
        XCTAssertNotEqual(work.branding.crest.symbol, personal.branding.crest.symbol)
        XCTAssertTrue(
            session.spaces
                .flatMap(\.tabs)
                .compactMap(\.url)
                .allSatisfy { $0.scheme == "data" }
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

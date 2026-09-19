import CloudKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserGettingStartedTests: XCTestCase {
    func testNativeStateSurvivesSelectionAndEndsAtExplicitUnload() throws {
        let browser = BrowserStore.preview()
        let pages = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let id = try XCTUnwrap(browser.openGettingStarted())
        pages.select(session: browser.session)
        let space = try XCTUnwrap(browser.selectedSpace)
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profile.id)
        let runtime = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        let state = runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        state.chapter = 1
        state.practice.makeSplit()
        let members = state.practice.members.map(\.id)
        browser.openNewTab()
        pages.select(session: browser.session)
        browser.selectTab(id)
        pages.select(session: browser.session)
        XCTAssertTrue(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted) === runtime)
        XCTAssertEqual(state.chapter, 1)
        XCTAssertEqual(state.practice.members.map(\.id), members)
        XCTAssertFalse(
            pages.closeDurablePage(
                BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()), discardState: false))
        XCTAssertTrue(pages.nativeTabs.contains(assignment))
        XCTAssertTrue(
            BrowserDurableTabCloseAction(
                browser: browser, spaceAccess: BrowserSpaceAccessController(),
                closePage: { pages.closeDurablePage($0, discardState: $1) }
            ).perform(assignment))
        XCTAssertTrue(browser.selectedSpace?.tabs.contains(where: { $0.id == id }) == true)
        XCTAssertNil(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        browser.selectTab(id)
        pages.select(session: browser.session)
        let reopened = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertFalse(reopened === runtime)
        XCTAssertEqual(reopened.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }.chapter, 0)
    }

    func testNativeStateIsScopedToWindowAssignmentAndDescriptor() throws {
        let browser = BrowserStore.preview()
        let id = try XCTUnwrap(browser.openGettingStarted())
        let space = try XCTUnwrap(browser.selectedSpace)
        var tab = try XCTUnwrap(browser.selectedTab)
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profile.id)
        let first = BrowserNativeTabStore()
        let second = BrowserNativeTabStore()
        first.load(tab: tab, space: space)
        second.load(tab: tab, space: space)
        let runtime = try XCTUnwrap(first.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertFalse(second.runtime(matching: assignment, content: .gettingStarted) === runtime)
        let stale = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: BrowsingProfile().id)
        XCTAssertFalse(first.remove(tabID: id, matching: stale))
        tab = BrowserTab(id: id, title: "Settings", url: nil, nativeContent: .settings, placement: .saved)
        first.load(tab: tab, space: space)
        XCTAssertNil(first.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertNotNil(first.runtime(matching: assignment, content: .settings))
        let replacement = BrowserSpace(
            id: space.id, profile: BrowsingProfile(), name: space.name, symbol: space.symbol,
            accent: space.accent, folders: [], tabs: [tab], selectedTabID: tab.id)
        first.reconcile(session: BrowserSession(spaces: [replacement], selectedSpaceID: replacement.id))
        XCTAssertTrue(first.tabIDs.isEmpty)
        first.load(tab: tab, space: replacement)
        first.reconcile(validTabIDs: [])
        XCTAssertTrue(first.tabIDs.isEmpty)
    }

    func testNativePressurePreservesPresentedCardsAndWindowTeardownReleasesState() async throws {
        let browser = BrowserStore.preview()
        let pages = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let guide = try XCTUnwrap(browser.openGettingStarted())
        pages.select(session: browser.session)
        let settings = try XCTUnwrap(browser.openSettings())
        pages.select(session: browser.session)
        pages.handleMemoryPressure(.critical)
        await pages.waitForPendingMemoryPressureResponse()
        XCTAssertFalse(pages.nativeTabs.tabIDs.contains(guide))
        XCTAssertTrue(pages.nativeTabs.tabIDs.contains(settings))
        await pages.releaseWindowRuntime(for: try XCTUnwrap(browser.selectedSpace))
        XCTAssertTrue(pages.nativeTabs.tabIDs.isEmpty)
    }

    func testNativeGuideReusesItsTabAndNeverAllocatesWebKit() throws {
        let browser = BrowserStore.preview()
        let first = try XCTUnwrap(browser.openGettingStarted())
        XCTAssertEqual(browser.openGettingStarted(), first)
        XCTAssertEqual(browser.selectedSpace?.tabs.filter { $0.nativeContent == .gettingStarted }.count, 1)
        XCTAssertNil(browser.selectedTab?.url)
        XCTAssertFalse(try XCTUnwrap(browser.selectedTab).isStartPage)
        let pages = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        pages.select(session: browser.session)
        XCTAssertEqual(pages.activeTabID, first)
        XCTAssertEqual(pages.presentedTabIDs, [first])
        XCTAssertNil(pages.activePage)
        XCTAssertFalse(pages.retainedTabIDs.contains(first))
        XCTAssertFalse(pages.retainedTabIDs.contains(first))
        pages.selectSpace(in: browser)
        XCTAssertEqual(browser.selectedTab?.id, first)
    }

    func testNativeDescriptorSurvivesRepairDuplicationAndUnknownKind() throws {
        let browser = BrowserStore.preview()
        let unknown = BrowserNativeTabContent(kind: "future-notes", resourceID: UUID())
        let id = try XCTUnwrap(browser.openNativeTab(unknown, title: "My notes", symbol: "note.text"))
        var session = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(browser.session))
        session.repairRuntimeIntegrity()
        XCTAssertEqual(session.selectedTab?.nativeContent, unknown)
        XCTAssertEqual(session.selectedTab?.title, "My notes")
        let copyID = try XCTUnwrap(session.duplicateTab(id, in: session.selectedSpaceID))
        XCTAssertEqual(session.selectedTab?.id, copyID)
        XCTAssertEqual(session.selectedTab?.nativeContent, unknown)
        session.closeTab(copyID)
        session.repairRuntimeIntegrity()
        XCTAssertEqual(session.selectedSpace?.archivedTabs.last?.tab.nativeContent, unknown)
    }

    func testLegacyTabsDecodeAndNavigatingNativeTabBecomesAWebsite() throws {
        let tab = BrowserTab(title: "Guide", url: nil, nativeContent: .gettingStarted, placement: .current)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(tab)) as? [String: Any])
        object.removeValue(forKey: "nativeContent")
        let legacy = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(legacy.isStartPage)
        var converted = tab
        converted.url = URL(string: "https://example.com")!
        XCTAssertNil(converted.nativeContent)
        XCTAssertTrue(converted.isWebPage)
    }

    func testNativeTabsStayLocalWhilePortableExportPreservesContent() throws {
        let browser = BrowserStore.preview()
        let id = try XCTUnwrap(browser.openGettingStarted())
        // Whole-second fixture avoids Date epoch-conversion rounding in the
        // existing JSON cloud codec; this test checks descriptor preservation.
        for spaceIndex in browser.session.spaces.indices {
            for tabIndex in browser.session.spaces[spaceIndex].tabs.indices {
                browser.session.spaces[spaceIndex].tabs[tabIndex].lastActivatedAt = Date(
                    timeIntervalSince1970: 1_700_000_000)
            }
        }
        let payloads = try BrowserSyncProjection.payloads(
            from: browser.session, preferences: .default, existingRecords: [])
        let records = payloads.map {
            BrowserSyncRecord.save($0, version: BrowserSyncVersion(logicalClock: 1, deviceID: UUID()))
        }
        XCTAssertFalse(records.contains { $0.id.value == id.rawValue })
        let restored = try BrowserSyncMaterializer.materialize(
            records: records, preferences: .default, localSession: browser.session)
        XCTAssertEqual(restored.selectedSpace?.tabs.first { $0.id == id }?.nativeContent, .gettingStarted)
        let archive = try JSONDecoder().decode(
            BrowserPortableArchive.self, from: JSONEncoder().encode(BrowserPortableArchive(session: browser.session)))
        let imported = try archive.materialize()
        XCTAssertEqual(imported.spaces.flatMap(\.tabs).filter { $0.nativeContent == .gettingStarted }.count, 1)
    }

    func testNativeActionsRejectAStaleProfileAndKeepGuideWhenOpeningALink() throws {
        let browser = BrowserStore.preview()
        let id = try XCTUnwrap(browser.openGettingStarted())
        let space = try XCTUnwrap(browser.selectedSpace)
        var opened = 0
        let actions = BrowserNativeTabActions(
            browser: browser, spaceAccess: BrowserSpaceAccessController(), didOpenURL: { opened += 1 })
        let url = URL(string: "https://example.com")!
        actions.openURL(
            BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()), .gettingStarted, url)
        XCTAssertEqual(opened, 0)
        actions.openURL(
            BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profile.id), .gettingStarted, url
        )
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(browser.selectedTab?.url, url)
        XCTAssertEqual(browser.selectedSpace?.tabs.first { $0.id == id }?.nativeContent, .gettingStarted)
    }

}

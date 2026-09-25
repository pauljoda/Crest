import CloudKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserGettingStartedTests: XCTestCase {
    func testNativeStateSurvivesSelectionAndEndsAtExplicitUnload() throws {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let id = try XCTUnwrap(browser.openGettingStarted())
        pages.select(session: browser.presented)
        let space = try XCTUnwrap(browser.selectedSpace)
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profile.id)
        let runtime = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        let state = runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        state.chapter = 1
        state.practice.makeSplit()
        let members = state.practice.members.map(\.id)
        browser.openNewTab()
        pages.select(session: browser.presented)
        browser.selectTab(id)
        pages.select(session: browser.presented)
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
        pages.select(session: browser.presented)
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
            accent: space.accent, folders: [], tabs: [tab])
        first.reconcile(session: BrowserSession(spaces: [replacement]))
        XCTAssertTrue(first.tabIDs.isEmpty)
        first.load(tab: tab, space: replacement)
        first.reconcile(validTabIDs: [])
        XCTAssertTrue(first.tabIDs.isEmpty)
    }

    func testNativePressurePreservesPresentedCardsAndWindowTeardownReleasesState() async throws {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let guide = try XCTUnwrap(browser.openGettingStarted())
        pages.select(session: browser.presented)
        let settings = try XCTUnwrap(browser.openSettings())
        pages.select(session: browser.presented)
        pages.handleMemoryPressure(.critical)
        await pages.waitForPendingMemoryPressureResponse()
        XCTAssertFalse(pages.nativeTabs.tabIDs.contains(guide))
        XCTAssertTrue(pages.nativeTabs.tabIDs.contains(settings))
        await pages.releaseWindowRuntime(for: try XCTUnwrap(browser.selectedSpace))
        XCTAssertTrue(pages.nativeTabs.tabIDs.isEmpty)
    }

    func testNativeGuideReusesItsTabAndNeverAllocatesWebKit() throws {
        let browser = BrowserStore.hostingPages()
        let first = try XCTUnwrap(browser.openGettingStarted())
        XCTAssertEqual(browser.openGettingStarted(), first)
        XCTAssertEqual(browser.selectedSpace?.tabs.filter { $0.nativeContent == .gettingStarted }.count, 1)
        XCTAssertNil(browser.selectedTab?.url)
        XCTAssertFalse(try XCTUnwrap(browser.selectedTab).isStartPage)
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        pages.select(session: browser.presented)
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
        let spaceID = browser.selectedSpaceID
        var session = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(browser.session))
        session = try BrowserCoreSync.repair(session)
        let repaired = session.space(id: spaceID)?.tabs.first { $0.id == id }
        XCTAssertEqual(repaired?.nativeContent, unknown)
        XCTAssertEqual(repaired?.title, "My notes")
        let copyID = try XCTUnwrap(browser.duplicateTab(id, in: spaceID))
        XCTAssertEqual(browser.session.space(id: spaceID)?.tabs.first { $0.id == copyID }?.nativeContent, unknown)
        XCTAssertTrue(browser.closeTab(copyID, in: spaceID))
        session = try BrowserCoreSync.repair(browser.session)
        XCTAssertEqual(session.space(id: spaceID)?.archivedTabs.last?.tab.nativeContent, unknown)
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
        var session = browser.session
        for spaceIndex in session.spaces.indices {
            for tabIndex in session.spaces[spaceIndex].tabs.indices {
                session.spaces[spaceIndex].tabs[tabIndex].lastActivatedAt = Date(timeIntervalSince1970: 1_700_000_000)
            }
        }
        let payloads = try BrowserCoreSync.project(session, preferences: .default, records: [])
        let records = payloads.map {
            BrowserSyncRecord.save($0, version: BrowserSyncVersion(logicalClock: 1, deviceID: UUID()))
        }
        XCTAssertFalse(records.contains { $0.id.value == id.rawValue })
        let restored = try BrowserCoreSync.materialize(session, preferences: .default, records: records)
        XCTAssertEqual(
            restored.space(id: browser.selectedSpaceID)?.tabs.first { $0.id == id }?.nativeContent, .gettingStarted)
        let archive = try JSONDecoder().decode(
            BrowserPortableArchive.self, from: JSONEncoder().encode(BrowserPortableArchive(session: session)))
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

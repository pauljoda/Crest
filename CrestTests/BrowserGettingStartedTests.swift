import CloudKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserGettingStartedTests: XCTestCase {
    func testOnboardingIsolationStartsWithTheRealFreshInstallSeed() {
        let environment = BrowserLaunchEnvironment(values: ["CREST_SHOW_ONBOARDING": "1"], isXCTestRuntime: false)
        let browser = BrowserStore.isolatedLaunch(launchEnvironment: environment)
        XCTAssertEqual(browser.session.spaces.count, 1)
        XCTAssertTrue(browser.session.hasDisposableSeedState)
        XCTAssertEqual(browser.selectedSpace?.branding.iconStyle, .layeredCrest)
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
        pages.prepareExtensionSelection(session: browser.session)
        pages.prepareExtensionTab(for: first, in: browser.session.selectedSpaceID, session: browser.session)
        XCTAssertFalse(pages.retainedTabIDs.contains(first))
        pages.selectSpace(in: browser)
        XCTAssertEqual(browser.selectedTab?.id, first)
    }

    func testSettingsTabIsReusedPersistsAndNeverAllocatesWebKit() throws {
        let browser = BrowserStore.preview()
        let id = try XCTUnwrap(browser.openSettings())
        XCTAssertEqual(browser.openSettings(), id)
        XCTAssertEqual(browser.selectedSpace?.tabs.filter { $0.nativeContent == .settings }.count, 1)
        XCTAssertEqual(browser.selectedTab?.placement, .current)
        XCTAssertNil(browser.selectedTab?.url)
        let restored = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(browser.session))
        XCTAssertEqual(restored.selectedTab?.nativeContent, .settings)
        let pages = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        pages.select(session: browser.session)
        XCTAssertEqual(pages.activeTabID, id)
        XCTAssertNil(pages.activePage)
        XCTAssertFalse(pages.retainedTabIDs.contains(id))
        browser.closeTab(id)
        XCTAssertFalse(browser.selectedSpace?.tabs.contains { $0.id == id } ?? true)
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

    func testPracticeMutatesOnlyItsOwnStoreAndKeepsSavedTabsWhenClearing() {
        let practice = BrowserGettingStartedPractice()
        practice.browser.pinTab(practice.mailID)
        practice.browser.saveTab(practice.trailID)
        practice.addFolder(nested: true)
        XCTAssertEqual(practice.space.folders.count, 2)
        XCTAssertNotNil(practice.space.folders.last?.parentID)
        XCTAssertTrue(practice.tabActions.clearCurrentTabs())
        XCTAssertTrue(practice.space.pinnedTabs.contains { $0.id == practice.mailID })
        XCTAssertTrue(practice.space.savedTabs.contains { $0.id == practice.trailID })
        XCTAssertTrue(practice.space.currentTabs.isEmpty)
        practice.reset()
        XCTAssertEqual(practice.space.currentTabs.count, 3)
        XCTAssertNil(practice.browser.syncCoordinator)
        XCTAssertTrue(practice.browser.persistence is InMemoryBrowserSessionPersistence)
    }

    func testNativeSyncAndPortableExportPreserveContent() throws {
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
        let native = try XCTUnwrap(records.first { $0.id.value == id.rawValue })
        let codec = BrowserCloudRecordCodec()
        let cloud = try codec.encode(native)
        XCTAssertEqual((cloud["schemaVersion"] as? NSNumber)?.intValue, 3)
        XCTAssertEqual(try codec.decode(cloud), native)
        let restored = try BrowserSyncMaterializer.materialize(
            records: records, preferences: .default, localSession: browser.session)
        XCTAssertEqual(restored.selectedSpace?.tabs.first { $0.id == id }?.nativeContent, .gettingStarted)
        let archive = try JSONDecoder().decode(
            BrowserPortableArchive.self, from: JSONEncoder().encode(BrowserPortableArchive(session: browser.session)))
        let imported = try archive.materialize()
        XCTAssertEqual(imported.spaces.flatMap(\.tabs).filter { $0.nativeContent == .gettingStarted }.count, 1)
    }

    func testMixedSplitAllocatesOnlyItsWebsiteAndPreservesNativeFocus() throws {
        let browser = BrowserStore.preview()
        let native = try XCTUnwrap(browser.openGettingStarted())
        let website = try XCTUnwrap(browser.openNewTab(url: URL(string: "about:blank")!))
        let space = try XCTUnwrap(browser.selectedSpace)
        XCTAssertTrue(
            browser.addTabToSplit(
                BrowserTabDragItem(tabID: native, spaceID: space.id, profileID: space.profile.id), joining: website,
                at: nil))
        let members = try XCTUnwrap(browser.selectedSpace).presentedSplitMembers(for: browser.selectedTab?.id)
        let copy = try XCTUnwrap(members.first { $0.nativeContent != nil })
        browser.selectTab(copy.id)
        let pages = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        pages.select(session: browser.session)
        XCTAssertEqual(pages.activeTabID, copy.id)
        XCTAssertNil(pages.activePage)
        XCTAssertEqual(Set(pages.presentedTabIDs), Set(members.map(\.id)))
        XCTAssertTrue(pages.retainedTabIDs.contains(website))
        XCTAssertFalse(pages.retainedTabIDs.contains(copy.id))
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

    func testDismissingSavedNativeViewKeepsItsTabAndRejectsAStaleAssignment() throws {
        let browser = BrowserStore.preview()
        let id = try XCTUnwrap(browser.openGettingStarted())
        let space = try XCTUnwrap(browser.selectedSpace)
        browser.dismissNativeTab(id, matching: BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: UUID()))
        XCTAssertEqual(browser.selectedTab?.id, id)
        browser.dismissNativeTab(id, matching: BrowserSpaceRuntimeAssignment(space: space))
        XCTAssertNotEqual(browser.selectedTab?.id, id)
        XCTAssertEqual(browser.selectedSpace?.tabs.first { $0.id == id }?.nativeContent, .gettingStarted)
        XCTAssertEqual(browser.openGettingStarted(), id)
    }

    func testPracticeHasBundledFaviconsAndReordersRealSplitMembers() throws {
        let practice = BrowserGettingStartedPractice()
        XCTAssertTrue(practice.space.tabs.allSatisfy { $0.faviconData?.isEmpty == false })
        practice.makeSplit()
        let before = practice.members.map(\.id)
        XCTAssertEqual(before.count, 2)
        let last = try XCTUnwrap(before.last)
        practice.move(last, by: -1)
        XCTAssertEqual(practice.members.map(\.id), before.reversed())
        XCTAssertEqual(practice.space.selectedTabID, last)
        practice.openExampleTab()
        XCTAssertNotNil(practice.browser.selectedTab?.faviconData)
    }

    func testFirstRunMovesIntoSetupAndImportReturnsToSpaceCustomization() {
        XCTAssertEqual(BrowserMacOnboardingPolicy.nextFirstRunStep(after: .welcome), .importBrowser)
        XCTAssertEqual(BrowserMacOnboardingPolicy.destinationAfterImport(for: .firstRun), .manualSetup)
        XCTAssertEqual(BrowserMacOnboardingPolicy.destinationAfterImport(for: .importBrowser), .complete)
    }
}

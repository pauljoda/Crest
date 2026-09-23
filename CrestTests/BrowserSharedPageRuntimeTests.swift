import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserSharedPageRuntimeTests: XCTestCase {
    func testSnapshotEngineCompletesOnlyCommittedNavigations() throws {
        let tab = BrowserTab.startPage()
        let space = makeSpace(tabs: [tab])
        let pool = BrowserPagePool()
        defer { pool.reconcile(validTabIDs: []) }
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)
        let url = try XCTUnwrap(URL(string: "https://example.com/first"))
        var state = BrowserPageEngineState(
            url: url, title: "First", isLoading: true,
            security: .secure, themeColor: nil,
            canGoBack: false, canGoForward: false, failure: nil, committed: false)

        page.receive(.navigationStarted)
        page.receive(.stateChanged(state))
        state.committed = true
        page.receive(.stateChanged(state))
        XCTAssertEqual(page.completedNavigationCount, 0)
        state.committed = false
        state.isLoading = false
        page.receive(.stateChanged(state))
        XCTAssertEqual(page.completedNavigationCount, 1)

        page.receive(.navigationStarted)
        state.isLoading = true
        page.receive(.stateChanged(state))
        state.isLoading = false
        page.receive(.stateChanged(state))
        XCTAssertEqual(page.completedNavigationCount, 1)

        state.url = try XCTUnwrap(URL(string: "https://example.com/first#section"))
        state.committed = true
        page.receive(.stateChanged(state))
        XCTAssertEqual(page.completedNavigationCount, 2)
    }

    func testNormalWindowsShareLivePagesButKeepIndependentSelections() throws {
        let tabs = [BrowserTab.startPage(), BrowserTab.startPage()]
        let space = makeSpace(tabs: tabs)
        let runtimeStore = BrowserPageRuntimeStore()
        let first = BrowserPagePool(runtimeStore: runtimeStore)
        let second = BrowserPagePool(runtimeStore: runtimeStore)
        first.select(tab: tabs[0], space: space)
        let original = try XCTUnwrap(first.activePage)
        second.select(tab: tabs[1], space: space)
        XCTAssertEqual(first.activeTabID, tabs[0].id)
        XCTAssertEqual(second.activeTabID, tabs[1].id)
        second.select(tab: tabs[0], space: space)
        XCTAssertTrue(second.activePage === original)
        XCTAssertTrue(first.activePage === original)

        second.setWindowFocused(true)
        XCTAssertNil(first.presentedPage(for: tabs[0].id))
        XCTAssertTrue(first.isMirroringPage(for: tabs[0].id))
        XCTAssertTrue(second.presentedPage(for: tabs[0].id) === original)
        first.setWindowFocused(true)
        XCTAssertTrue(first.presentedPage(for: tabs[0].id) === original)
        XCTAssertTrue(second.isMirroringPage(for: tabs[0].id))
    }

    func testClosingAWindowReleasesOnlyItsClaimAndTransfersRouting() throws {
        let tab = BrowserTab.startPage()
        let space = makeSpace(tabs: [tab])
        let runtimeStore = BrowserPageRuntimeStore()
        let first = BrowserPagePool(runtimeStore: runtimeStore)
        let second = BrowserPagePool(runtimeStore: runtimeStore)
        first.select(tab: tab, space: space)
        second.select(tab: tab, space: space)
        second.setWindowFocused(true)
        let page = try XCTUnwrap(second.activePage)
        page.translation.setActive(true, in: page.webView)
        page.translation.sourceID = "es"
        page.translation.targetID = "en"
        page.translation.start()
        second.releaseWindowPresentation()
        XCTAssertTrue(first.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.host === first)
        XCTAssertTrue(first.containsResidentPage(for: tab.id))
        XCTAssertTrue(
            page.translation.isWorking, "Closing a presenter must preserve work still visible in another window.")
        page.translation.suspend()
    }

    func testLiveTransferPreservesPageAndRejectsDifferentProfiles() throws {
        let tab = BrowserTab.startPage()
        let space = makeSpace(tabs: [tab])
        let source = BrowserPagePool()
        let destination = BrowserPagePool()
        source.select(tab: tab, space: space)
        let page = try XCTUnwrap(source.activePage)
        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        let invalidSpace = BrowserSpace(
            id: space.id, profile: BrowsingProfile(), name: space.name,
            symbol: space.symbol, accent: space.accent, folders: [], tabs: [tab], selectedTabID: tab.id)
        XCTAssertFalse(destination.transferTabRuntime(from: source, matching: assignment, as: tab, in: invalidSpace))
        XCTAssertTrue(source.activePage === page)
        XCTAssertTrue(destination.transferTabRuntime(from: source, matching: assignment, as: tab, in: space))
        XCTAssertFalse(source.containsResidentPage(for: tab.id))
        destination.select(tab: tab, space: space)
        XCTAssertTrue(destination.activePage === page)
        XCTAssertTrue(page.host === destination)
    }

    func testMemoryPressureProtectsPagesPresentedByOtherWindows() async throws {
        let tabs = (0..<4).map { _ in BrowserTab.startPage() }
        let space = makeSpace(tabs: tabs)
        let runtimeStore = BrowserPageRuntimeStore()
        var decisions = 0
        var laterDecision: CheckedContinuation<Void, Never>?
        defer { laterDecision?.resume() }
        let first = BrowserPagePool(
            runtimeStore: runtimeStore,
            residencyDecisionProvider: { _, _ in
                decisions += 1
                if decisions == 2 {
                    await withCheckedContinuation { laterDecision = $0 }
                }
                return BrowserPageResidencyDecision(
                    isSelected: false, keepsPageLoaded: false, isPlayingMedia: false, isCapturingMedia: false)
            })
        let second = BrowserPagePool(runtimeStore: runtimeStore)
        first.select(tab: tabs[0], space: space, at: Date(timeIntervalSince1970: 1))
        first.select(tab: tabs[1], space: space, at: Date(timeIntervalSince1970: 2))
        second.select(tab: tabs[0], space: space, at: Date(timeIntervalSince1970: 3))
        first.select(tab: tabs[2], space: space, at: Date(timeIntervalSince1970: 4))
        first.select(tab: tabs[3], space: space, at: Date(timeIntervalSince1970: 5))
        let returningPage = try XCTUnwrap(
            first.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: tabs[1].id, spaceID: space.id, profileID: space.profile.id)))
        first.handleMemoryPressure(.critical)
        try await waitUntil { laterDecision != nil }
        // The first candidate was approved before WebKit began evaluating the
        // second. Bringing it into another window must still protect its page.
        second.select(tab: tabs[1], space: space, at: Date(timeIntervalSince1970: 6))
        let decision = try XCTUnwrap(laterDecision)
        laterDecision = nil
        decision.resume()
        await first.waitForPendingMemoryPressureResponse()
        XCTAssertTrue(second.containsResidentPage(for: tabs[0].id))
        XCTAssertTrue(second.presentedPage(for: tabs[1].id) === returningPage)
        XCTAssertTrue(second.activePage === returningPage)
        XCTAssertTrue(first.containsResidentPage(for: tabs[3].id))
        XCTAssertFalse(first.containsResidentPage(for: tabs[2].id))
    }

    func testWindowHandoffAndWorkspaceTransferPreserveTheLiveDocumentAndHistory() async throws {
        let tab = BrowserTab.startPage()
        let space = makeSpace(tabs: [tab])
        let owner = BrowserPageRuntimeStore()
        let first = BrowserPagePool(runtimeStore: owner)
        let second = BrowserPagePool(runtimeStore: owner)
        let blank = BrowserPagePool()
        defer {
            first.reconcile(validTabIDs: [])
            blank.closeWindowWorkspace()
        }
        first.select(tab: tab, space: space)
        let page = try XCTUnwrap(first.activePage)
        let firstHost = BrowserWebHostView()
        let secondHost = BrowserWebHostView()
        let blankHost = BrowserWebHostView()
        let windows = [firstHost, secondHost, blankHost].map { host in
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            return window
        }
        defer { for window in windows { window.close() } }
        firstHost.attach(page.webView, allowsAttachment: true)
        let url = try XCTUnwrap(URL(string: "https://handoff.crest.test/form"))
        page.webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: "<html><body><textarea id='draft'></textarea></body></html>")
        try await waitUntil { page.webView.url == url && !page.webView.isLoading }
        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('draft').value = 'unsaved draft'; history.pushState({draft: 7}, '', '#edited');")
        let currentURL = page.webView.url
        let history = page.webView.backForwardList.backList.map(\.url)

        second.select(tab: tab, space: space)
        second.setWindowFocused(true)
        secondHost.attach(page.webView, allowsAttachment: second.presentedPage(for: tab.id) === page)
        firstHost.attach(page.webView, allowsAttachment: first.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.webView.window === windows[1])
        XCTAssertTrue(page.webView.superview === secondHost)

        first.setWindowFocused(true)
        firstHost.attach(page.webView, allowsAttachment: first.presentedPage(for: tab.id) === page)
        secondHost.attach(page.webView, allowsAttachment: second.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.webView.window === windows[0])
        XCTAssertTrue(page.webView.superview === firstHost)

        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        XCTAssertTrue(blank.transferTabRuntime(from: first, matching: assignment, as: tab, in: space))
        blank.select(tab: tab, space: space)
        blankHost.attach(page.webView, allowsAttachment: blank.presentedPage(for: tab.id) === page)
        let staleHost = BrowserWebHostView()
        staleHost.attach(page.webView, allowsAttachment: first.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.webView.window === windows[2])
        XCTAssertTrue(page.webView.superview === blankHost)
        XCTAssertFalse(first.containsResidentPage(for: tab.id))
        XCTAssertFalse(second.containsResidentPage(for: tab.id))
        XCTAssertTrue(blank.activePage === page)
        XCTAssertEqual(page.webView.url, currentURL)
        XCTAssertEqual(page.webView.backForwardList.backList.map(\.url), history)
        let draft = try await page.webView.evaluateJavaScript("document.getElementById('draft').value") as? String
        let historyState = try await page.webView.evaluateJavaScript("history.state.draft") as? Int
        XCTAssertEqual(draft, "unsaved draft")
        XCTAssertEqual(historyState, 7)
    }

    func testPageCallbacksAndSingleMetadataPublisherFollowTheCurrentWorkspaceOwner() async throws {
        let tab = BrowserTab.startPage()
        let space = makeSpace(tabs: [tab])
        let owner = BrowserPageRuntimeStore()
        owner.publishesPageMetadataCentrally = true
        let blankOwner = BrowserPageRuntimeStore()
        blankOwner.publishesPageMetadataCentrally = true
        var links: [String] = []
        var updates: [String] = []
        let first = BrowserPagePool(
            runtimeStore: owner,
            openModifiedLink: { _, _, _ in
                links.append("first")
                return nil
            },
            backgroundPageDidUpdate: { _ in
                updates.append("first")
                return nil
            })
        let second = BrowserPagePool(
            runtimeStore: owner,
            openModifiedLink: { _, _, _ in
                links.append("second")
                return nil
            },
            backgroundPageDidUpdate: { _ in
                updates.append("second")
                return nil
            })
        let blank = BrowserPagePool(
            runtimeStore: blankOwner,
            openModifiedLink: { _, _, _ in
                links.append("blank")
                return nil
            },
            backgroundPageDidUpdate: { _ in
                updates.append("blank")
                return nil
            })
        defer {
            first.reconcile(validTabIDs: [])
            blank.closeWindowWorkspace()
        }
        first.select(tab: tab, space: space)
        let page = try XCTUnwrap(first.activePage)
        second.select(tab: tab, space: space)
        second.setWindowFocused(true)
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://callback.crest.test/")))
        page.openModifiedLink(request, space.id, false)
        page.completedNavigationCount += 1
        try await waitUntil { updates.count == 1 }
        XCTAssertEqual(links, ["second"])
        XCTAssertEqual(updates, ["second"])

        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        XCTAssertTrue(blank.transferTabRuntime(from: second, matching: assignment, as: tab, in: space))
        blank.select(tab: tab, space: space)
        page.openModifiedLink(request, space.id, false)
        page.completedNavigationCount += 1
        try await waitUntil { updates.count == 2 }
        XCTAssertEqual(links, ["second", "blank"])
        XCTAssertEqual(updates, ["second", "blank"])
    }

    func testNativeTabMovePreservesItsLoadedModelAcrossWorkspaceOwners() throws {
        let tab = BrowserTab(title: "Getting Started", url: nil, nativeContent: .gettingStarted, placement: .current)
        let space = makeSpace(tabs: [tab])
        let source = BrowserPagePool()
        let destination = BrowserPagePool()
        source.select(tab: tab, space: space)
        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        let runtime = try XCTUnwrap(source.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        let model = runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        model.chapter = 2
        XCTAssertTrue(destination.transferTabRuntime(from: source, matching: assignment, as: tab, in: space))
        destination.select(tab: tab, space: space)
        XCTAssertFalse(source.nativeTabs.contains(assignment))
        XCTAssertTrue(destination.nativeTabs.runtime(matching: assignment, content: .gettingStarted) === runtime)
        XCTAssertEqual(runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }.chapter, 2)
    }

    func testAnUnloadedTabTransfersItsArchivedHistoryWithoutLeavingSourceState() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "crest-window-tab-state-\(UUID())")
        let archive = BrowserTabStateArchive(rootDirectory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var tab = BrowserTab.startPage()
        let space = makeSpace(tabs: [tab])
        let source = BrowserPagePool(usesEphemeralWebsiteDataStores: false, tabStateArchive: archive)
        let destination = BrowserPagePool()
        defer {
            source.reconcile(validTabIDs: [])
            destination.closeWindowWorkspace()
        }
        source.select(tab: tab, space: space)
        let original = try XCTUnwrap(source.activePage)
        let firstURL = try XCTUnwrap(URL(string: "https://unloaded-transfer.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://unloaded-transfer.crest.test/two"))
        for url in [firstURL, secondURL] {
            original.webView.loadSimulatedRequest(
                URLRequest(url: url), responseHTML: "<html><body>History</body></html>")
            try await waitUntil { original.webView.url == url && !original.webView.isLoading }
        }
        tab.url = secondURL
        source.unloadPage(for: tab.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(archive.archivedState(profileID: space.profile.id, tabID: tab.id))
        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)

        XCTAssertTrue(destination.transferTabRuntime(from: source, matching: assignment, as: tab, in: space))
        await source.flushPendingTabStateWrites()
        XCTAssertNil(archive.archivedState(profileID: space.profile.id, tabID: tab.id))
        destination.select(tab: tab, space: space)
        let restored = try XCTUnwrap(destination.activePage)
        XCTAssertFalse(restored === original)
        XCTAssertEqual(restored.webView.url, secondURL)
        XCTAssertEqual(restored.webView.backForwardList.backList.map(\.url), [firstURL])
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for the live page update.")
    }

    private func makeSpace(tabs: [BrowserTab]) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Shared", symbol: "globe", accent: .indigo,
            folders: [], tabs: tabs, selectedTabID: tabs.first?.id)
    }
}

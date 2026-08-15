import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserContentBlockingTests: XCTestCase {
    @MainActor
    func testBalancedProtectionCompilesOnlyCrestsBundledRuleList() async throws {
        let store = try isolatedRuleListStore()
        defer { store.remove() }
        let compiler = RecordingBuiltInRuleListCompiler()
        let provider = BrowserContentRuleListProvider(
            ruleListStore: store.store,
            compiler: compiler
        )

        let ruleLists = try await provider.balancedRuleLists()

        XCTAssertEqual(ruleLists.map(\.identifier), [BrowserContentBlockingRules.identifier])
        XCTAssertEqual(compiler.identifiers, [BrowserContentBlockingRules.identifier])
        XCTAssertEqual(compiler.sources, [BrowserContentBlockingRules.balancedSource])
    }

    func testBalancedProtectionIsTheDefaultAndRepairsLegacyPreferences() throws {
        XCTAssertEqual(
            BrowserSpaceBrowsingPreferences.default.contentBlockingPolicy,
            .balanced
        )

        let legacyJSON = """
            {
              "searchProvider": "duckDuckGo",
              "currentTabCleanupPolicy": "after24Hours"
            }
            """
        let decoded = try JSONDecoder().decode(
            BrowserSpaceBrowsingPreferences.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(decoded.searchProvider, .duckDuckGo)
        XCTAssertEqual(decoded.currentTabCleanupPolicy, .after24Hours)
        XCTAssertEqual(decoded.contentBlockingPolicy, .balanced)
    }

    func testContentBlockingPreferenceChangesOnlyTheTargetSpace() throws {
        var session = BrowserSession.preview
        let workID = try XCTUnwrap(session.spaces.first?.id)
        let personalID = try XCTUnwrap(session.spaces.last?.id)
        var workPreferences = try XCTUnwrap(
            session.space(id: workID)?.browsingPreferences
        )

        workPreferences.contentBlockingPolicy = .off
        session.updateBrowsingPreferences(workPreferences, in: workID)

        XCTAssertEqual(
            session.space(id: workID)?.browsingPreferences.contentBlockingPolicy,
            .off
        )
        XCTAssertEqual(
            session.space(id: personalID)?.browsingPreferences.contentBlockingPolicy,
            .balanced
        )
    }

    func testBalancedRulesBlockOnlyKnownThirdPartySubresources() throws {
        let data = try XCTUnwrap(
            BrowserContentBlockingRules.balancedSource.data(using: .utf8)
        )
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )
        let rule = try XCTUnwrap(rules.first)
        let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
        let action = try XCTUnwrap(rule["action"] as? [String: Any])
        let resourceTypes = try XCTUnwrap(trigger["resource-type"] as? [String])
        let urlFilters = try rules.map { rule in
            try XCTUnwrap(
                (rule["trigger"] as? [String: Any])?["url-filter"] as? String
            )
        }

        XCTAssertEqual(BrowserContentBlockingRules.identifier, "com.pauldavis.crest.content-blocking.balanced.v2")
        XCTAssertEqual(trigger["load-type"] as? [String], ["third-party"])
        XCTAssertFalse(resourceTypes.contains("document"))
        XCTAssertFalse(resourceTypes.contains("top-document"))
        XCTAssertTrue(resourceTypes.contains("script"))
        XCTAssertTrue(resourceTypes.contains("fetch"))
        XCTAssertTrue(
            rules.allSatisfy { rule in
                (rule["trigger"] as? [String: Any])?["if-domain"] == nil
            })
        XCTAssertTrue(urlFilters.contains { $0.contains("doubleclick\\.net") })
        XCTAssertTrue(urlFilters.contains { $0.contains("google-analytics\\.com") })
        XCTAssertEqual(action["type"] as? String, "block")
    }

    func testNativeRuleListBlocksAMatchingScriptWithoutBlockingTheDocument() async throws {
        let identifier = "com.pauldavis.crest.tests.content-blocking.\(UUID().uuidString)"
        let source = #"""
            [{
              "trigger": {
                "url-filter": "tracker-script\\.js$",
                "resource-type": ["script"]
              },
              "action": { "type": "block" }
            }]
            """#
        let ruleList = try await BrowserContentRuleListCompiler.compile(
            identifier: identifier,
            source: source
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crest-content-blocking-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("index.html")
        let scriptURL = directory.appendingPathComponent("tracker-script.js")
        let html = #"""
            <!doctype html><html><body>
              <p id="status">ready</p>
              <script src="tracker-script.js"></script>
            </body></html>
            """#
        try Data(html.utf8).write(to: documentURL)
        try Data("window.crestTrackerScriptLoaded = true;".utf8).write(to: scriptURL)
        let websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let webView = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(
                for: BrowsingProfile(),
                websiteDataStore: websiteDataStore
            )
        )
        let navigation = ContentBlockingNavigationWaiter(webView: webView)
        defer { releaseWebView(webView) }

        do {
            try await navigation.loadFileURL(
                documentURL,
                allowingReadAccessTo: directory
            )
            let controlScriptLoaded =
                try await webView.evaluateJavaScript(
                    "window.crestTrackerScriptLoaded === true"
                ) as? Bool
            XCTAssertEqual(controlScriptLoaded, true)

            webView.configuration.userContentController.add(ruleList)
            try await navigation.loadFileURL(
                documentURL,
                allowingReadAccessTo: directory
            )
            let documentLoaded =
                try await webView.evaluateJavaScript(
                    "document.querySelector('#status')?.textContent === 'ready'"
                ) as? Bool
            let trackerLoaded =
                try await webView.evaluateJavaScript(
                    "window.crestTrackerScriptLoaded === true"
                ) as? Bool
            XCTAssertEqual(documentLoaded, true)
            XCTAssertEqual(trackerLoaded, false)
        } catch {
            await BrowserContentRuleListCompiler.remove(identifier: identifier)
            throw error
        }
        await BrowserContentRuleListCompiler.remove(identifier: identifier)
    }

    func testPagePoolReconcilesThePolicyAcrossResidentAndRecoveredTransientPages() async throws {
        let store = try isolatedRuleListStore()
        defer { store.remove() }
        let ruleList = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.pool-reconciliation.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "crest-pool-reconciliation\\.js$"),
            store: store.store
        )
        let provider = StubContentRuleListProvider(generations: [[ruleList]])
        let firstTab = BrowserTab.startPage()
        let firstSpace = contentBlockingSpace(name: "Protected", tab: firstTab)
        var session = BrowserSession(
            spaces: [firstSpace],
            selectedSpaceID: firstSpace.id
        )
        let pool = BrowserPagePool(
            browsingMode: .privateBrowsing,
            contentRuleListProvider: provider
        )
        defer {
            for tabID in pool.retainedTabIDs {
                pool.unloadPage(for: tabID)
            }
        }

        await pool.prepareContentBlocking()
        XCTAssertNil(
            pool.contentBlockingErrorDescription,
            pool.contentBlockingErrorDescription ?? ""
        )
        pool.select(session: session)
        XCTAssertEqual(pool.activePage?.isContentBlockingActive, true)
        let transientLease = try XCTUnwrap(
            pool.makeTransientPageLease(
                url: URL(string: "about:blank")!,
                in: firstSpace
            )
        )
        XCTAssertEqual(transientLease.page?.isContentBlockingActive, true)

        let protectedSpaceID = try XCTUnwrap(session.selectedSpace?.id)
        var preferences = try XCTUnwrap(
            session.space(id: protectedSpaceID)?.browsingPreferences
        )
        preferences.contentBlockingPolicy = .off
        session.updateBrowsingPreferences(preferences, in: protectedSpaceID)
        await pool.reconcileContentBlocking(in: session)

        XCTAssertEqual(pool.activePage?.isContentBlockingActive, false)
        XCTAssertEqual(transientLease.page?.isContentBlockingActive, false)

        transientLease.setActive(false)
        pool.handleMemoryPressure(.warning)
        XCTAssertNil(transientLease.page)
        transientLease.restore()
        XCTAssertEqual(transientLease.page?.isContentBlockingActive, false)

    }

    func testTurningOffCrestProtectionPreservesAnotherInstalledRuleList() async throws {
        let crestIdentifier = "com.pauldavis.crest.tests.owned-rules.\(UUID().uuidString)"
        let extensionIdentifier = "com.pauldavis.crest.tests.extension-rules.\(UUID().uuidString)"
        let crestRuleList = try await BrowserContentRuleListCompiler.compile(
            identifier: crestIdentifier,
            source: blockingRuleSource(matching: "crest-script\\.js$")
        )
        let extensionRuleList = try await BrowserContentRuleListCompiler.compile(
            identifier: extensionIdentifier,
            source: blockingRuleSource(matching: "extension-script\\.js$")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crest-exact-rule-removal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let documentURL = directory.appendingPathComponent("index.html")
            try Data(
                #"""
                <!doctype html><html><body>
                  <script src="crest-script.js"></script>
                  <script src="extension-script.js"></script>
                </body></html>
                """#.utf8
            ).write(to: documentURL)
            try Data("window.crestOwnedScriptLoaded = true;".utf8).write(
                to: directory.appendingPathComponent("crest-script.js")
            )
            try Data("window.crestExtensionScriptLoaded = true;".utf8).write(
                to: directory.appendingPathComponent("extension-script.js")
            )

            let space = try XCTUnwrap(BrowserSession.preview.selectedSpace)
            let configuration = BrowserPageConfiguration.make(
                for: space.profile,
                websiteDataStore: .nonPersistent(),
                contentRuleList: crestRuleList
            )
            configuration.userContentController.add(extensionRuleList)
            let page = BrowserPage(
                configuration: configuration,
                dialogPresenter: BrowserDialogPresenter(),
                downloadCenter: BrowserDownloadCenter(),
                permissionCenter: BrowserSitePermissionCenter(),
                spaceID: space.id,
                profileID: space.profile.id,
                spaceName: space.name,
                contentRuleList: crestRuleList,
                openNewTab: { _ in }
            )
            defer { page.prepareForSpaceDeletion() }

            page.applyContentBlocking(policy: .off, balancedRuleList: crestRuleList)
            let startingNavigationCount = page.completedNavigationCount
            page.webView.loadFileURL(documentURL, allowingReadAccessTo: directory)
            try await waitForNavigation(after: startingNavigationCount, on: page)

            let crestScriptLoaded =
                try await page.webView.evaluateJavaScript(
                    "window.crestOwnedScriptLoaded === true"
                ) as? Bool
            let extensionScriptLoaded =
                try await page.webView.evaluateJavaScript(
                    "window.crestExtensionScriptLoaded === true"
                ) as? Bool
            XCTAssertEqual(crestScriptLoaded, true)
            XCTAssertEqual(extensionScriptLoaded, false)
        } catch {
            await BrowserContentRuleListCompiler.remove(identifier: crestIdentifier)
            await BrowserContentRuleListCompiler.remove(identifier: extensionIdentifier)
            throw error
        }
        await BrowserContentRuleListCompiler.remove(identifier: crestIdentifier)
        await BrowserContentRuleListCompiler.remove(identifier: extensionIdentifier)
    }

    func testFilterListUpdateSwapsRulesWithoutReloadingResidentPages() async throws {
        let documents = try TrackerDocuments()
        defer { documents.remove() }
        let store = try isolatedRuleListStore()
        defer { store.remove() }
        let firstGeneration = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.first-generation.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "first-tracker\\.js$"),
            store: store.store
        )
        let secondGeneration = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.second-generation.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "second-tracker\\.js$"),
            store: store.store
        )
        let provider = StubContentRuleListProvider(
            generations: [[firstGeneration], [secondGeneration]]
        )
        let activeTab = BrowserTab.startPage()
        let backgroundTab = BrowserTab.startPage()
        let space = contentBlockingSpace(
            name: "Protected",
            tabs: [activeTab, backgroundTab]
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pool = BrowserPagePool(
            browsingMode: .privateBrowsing,
            contentRuleListProvider: provider
        )
        defer {
            for tabID in pool.retainedTabIDs {
                pool.unloadPage(for: tabID)
            }
        }

        await pool.prepareContentBlocking()
        session.selectTab(backgroundTab.id)
        pool.select(session: session)
        let backgroundPage = try XCTUnwrap(pool.activePage)
        session.selectTab(activeTab.id)
        pool.select(session: session)
        let activePage = try XCTUnwrap(pool.activePage)
        XCTAssertFalse(activePage === backgroundPage)

        for page in [activePage, backgroundPage] {
            try await documents.load(into: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertEqual(trackers, [false, true])
            try await documents.markSentinel(in: page)
        }
        let activeNavigationCount = activePage.completedNavigationCount
        let backgroundNavigationCount = backgroundPage.completedNavigationCount

        await pool.reloadContentBlocking(in: session)

        // The swap must reach both pages without disturbing either document.
        try await Task.sleep(for: .milliseconds(400))
        for (page, navigationCount) in [
            (activePage, activeNavigationCount),
            (backgroundPage, backgroundNavigationCount),
        ] {
            let keptSentinel = try await documents.hasSentinel(in: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertEqual(page.completedNavigationCount, navigationCount)
            XCTAssertFalse(page.isLoading)
            XCTAssertTrue(keptSentinel)
            XCTAssertEqual(trackers, [false, true])
            XCTAssertEqual(page.isContentBlockingActive, true)
        }

        // The next navigation in each page is the one that answers to the new
        // rules: the first tracker is allowed again and the second is blocked.
        for page in [activePage, backgroundPage] {
            try await documents.load(into: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertEqual(trackers, [true, false])
        }
    }

    /// A protection change the person just made is answered on every card of
    /// the split they are looking at — the unfocused ones included — and on
    /// nothing that is off screen.
    func testProtectionChangeReloadsEveryPresentedCardAndOnlyThose() async throws {
        let documents = try TrackerDocuments()
        defer { documents.remove() }
        let store = try isolatedRuleListStore()
        defer { store.remove() }
        let ruleList = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.protection-change.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "first-tracker\\.js$"),
            store: store.store
        )
        let provider = StubContentRuleListProvider(generations: [[ruleList]])
        let splitGroupID = SplitGroupID()
        let activeTab = BrowserTab(
            title: "Focused card",
            url: nil,
            placement: .current,
            splitGroupID: splitGroupID
        )
        let companionTab = BrowserTab(
            title: "Unfocused card",
            url: nil,
            placement: .current,
            splitGroupID: splitGroupID
        )
        let backgroundTab = BrowserTab.startPage()
        let space = contentBlockingSpace(
            name: "Protected",
            tabs: [activeTab, companionTab, backgroundTab]
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pool = BrowserPagePool(
            browsingMode: .privateBrowsing,
            contentRuleListProvider: provider
        )
        defer {
            for tabID in pool.retainedTabIDs {
                pool.unloadPage(for: tabID)
            }
        }

        await pool.prepareContentBlocking()
        session.selectTab(backgroundTab.id)
        pool.select(session: session)
        let backgroundPage = try XCTUnwrap(pool.activePage)
        session.selectTab(activeTab.id)
        pool.select(session: session)
        let activePage = try XCTUnwrap(pool.activePage)
        let companionPage = try XCTUnwrap(
            pool.presentedPage(for: companionTab.id)
        )
        XCTAssertEqual(
            pool.presentedTabIDs,
            [activeTab.id, companionTab.id]
        )
        // Adopts the Space's current protection level, which is what a window
        // does as it opens. Nothing may reload for it.
        await pool.reconcileContentBlocking(in: session)

        for page in [activePage, companionPage, backgroundPage] {
            try await documents.load(into: page)
            try await documents.markSentinel(in: page)
        }
        let activeNavigationCount = activePage.completedNavigationCount
        let companionNavigationCount = companionPage.completedNavigationCount
        let backgroundNavigationCount = backgroundPage.completedNavigationCount

        var preferences = try XCTUnwrap(
            session.space(id: space.id)?.browsingPreferences
        )
        preferences.contentBlockingPolicy = .off
        session.updateBrowsingPreferences(preferences, in: space.id)
        await pool.reconcileContentBlocking(in: session)

        try await waitForNavigation(after: activeNavigationCount, on: activePage)
        try await waitForNavigation(
            after: companionNavigationCount,
            on: companionPage
        )
        for page in [activePage, companionPage] {
            let sentinel = try await documents.hasSentinel(in: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertFalse(sentinel)
            XCTAssertEqual(trackers, [true, true])
            XCTAssertEqual(page.isContentBlockingActive, false)
        }

        let backgroundSentinel = try await documents.hasSentinel(in: backgroundPage)
        XCTAssertEqual(
            backgroundPage.completedNavigationCount,
            backgroundNavigationCount
        )
        XCTAssertFalse(backgroundPage.isLoading)
        XCTAssertTrue(backgroundSentinel)
        XCTAssertEqual(backgroundPage.isContentBlockingActive, false)
    }

    private func isolatedRuleListStore() throws -> IsolatedRuleListStore {
        try IsolatedRuleListStore()
    }

    private func blockingRuleSource(matching urlFilter: String) -> String {
        let rules: [[String: Any]] = [
            [
                "trigger": [
                    "url-filter": urlFilter,
                    "resource-type": ["script"],
                ],
                "action": ["type": "block"],
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(decoding: data, as: UTF8.self)
    }

    private func contentBlockingSpace(
        name: String,
        tab: BrowserTab
    ) -> BrowserSpace {
        contentBlockingSpace(name: name, tabs: [tab])
    }

    private func contentBlockingSpace(
        name: String,
        tabs: [BrowserTab]
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: "shield",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs.first?.id
        )
    }

    private func releaseWebView(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    private func waitForNavigation(
        after startingCount: Int,
        on page: BrowserPage
    ) async throws {
        for _ in 0..<100 {
            if page.completedNavigationCount > startingCount { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for the local content-blocking document")
    }
}

private enum ContentBlockingTestError: Error {
    case releasedWebView
    case unavailableRuleListStore
    case navigationTimedOut
}

@MainActor
private final class RecordingBuiltInRuleListCompiler:
    BrowserContentRuleListCompiling
{
    private(set) var identifiers: [String] = []
    private(set) var sources: [String] = []

    func compile(
        identifiers: [String],
        sources: [String],
        store: WKContentRuleListStore
    ) async throws -> [WKContentRuleList] {
        self.identifiers = identifiers
        self.sources = sources
        return try await BrowserContentRuleListCompilerAdapter().compile(
            identifiers: identifiers,
            sources: sources,
            store: store
        )
    }
}

/// A rule-list store of its own, so a test never sweeps or reads compiled lists
/// belonging to the app or to another test.
@MainActor
private struct IsolatedRuleListStore {
    let store: WKContentRuleListStore
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "crest-rule-list-store-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        guard let store = WKContentRuleListStore(url: directory) else {
            throw ContentBlockingTestError.unavailableRuleListStore
        }
        self.store = store
    }

    func availableIdentifiers() async -> [String] {
        await BrowserContentRuleListCompiler.availableIdentifiers(store: store)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A local document with two tracker scripts and a sentinel a reload would wipe,
/// which is how these tests tell a rule-list swap from a reload.
@MainActor
private struct TrackerDocuments {
    private let directory: URL
    private let documentURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "crest-content-blocking-swap-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        documentURL = directory.appendingPathComponent("index.html")
        try Data(
            #"""
            <!doctype html><html><body>
              <p id="status">ready</p>
              <script src="first-tracker.js"></script>
              <script src="second-tracker.js"></script>
            </body></html>
            """#.utf8
        ).write(to: documentURL)
        try Data("window.crestFirstTrackerLoaded = true;".utf8).write(
            to: directory.appendingPathComponent("first-tracker.js")
        )
        try Data("window.crestSecondTrackerLoaded = true;".utf8).write(
            to: directory.appendingPathComponent("second-tracker.js")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func load(into page: BrowserPage) async throws {
        let startingCount = page.completedNavigationCount
        page.webView.loadFileURL(documentURL, allowingReadAccessTo: directory)
        for _ in 0..<200 {
            if page.completedNavigationCount > startingCount { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw ContentBlockingTestError.navigationTimedOut
    }

    /// Whether each tracker script ran in the document that is loaded now.
    func trackerState(in page: BrowserPage) async throws -> [Bool] {
        [
            try await boolean("window.crestFirstTrackerLoaded === true", in: page),
            try await boolean("window.crestSecondTrackerLoaded === true", in: page),
        ]
    }

    func markSentinel(in page: BrowserPage) async throws {
        _ = try await page.webView.evaluateJavaScript(
            "window.crestSentinel = 'kept'; true"
        )
    }

    func hasSentinel(in page: BrowserPage) async throws -> Bool {
        try await boolean("window.crestSentinel === 'kept'", in: page)
    }

    private func boolean(_ script: String, in page: BrowserPage) async throws -> Bool {
        try await page.webView.evaluateJavaScript(script) as? Bool ?? false
    }
}

/// Hands out one rule-list generation per request, standing in for the provider
/// recompiling after a filter-list update.
@MainActor
private final class StubContentRuleListProvider: BrowserContentRuleListProviding {
    private let generations: [[WKContentRuleList]]
    private var requestCount = 0

    init(generations: [[WKContentRuleList]]) {
        precondition(!generations.isEmpty)
        self.generations = generations
    }

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        defer { requestCount += 1 }
        return generations[min(requestCount, generations.count - 1)]
    }
}

@MainActor
private final class ContentBlockingNavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func loadFileURL(_ url: URL, allowingReadAccessTo directory: URL) async throws {
        guard let webView else { throw ContentBlockingTestError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadFileURL(url, allowingReadAccessTo: directory)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

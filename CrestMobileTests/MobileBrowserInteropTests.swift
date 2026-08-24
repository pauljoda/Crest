import Foundation
import Network
import UniformTypeIdentifiers
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserInteropTests: XCTestCase {
    func testMobilePageAdvertisesSafariCompatibleBrowserIdentity() async throws {
        let tab = BrowserTab(title: "Compatibility", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Compatibility",
            symbol: "globe",
            accent: .teal,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            websiteDataStore: .nonPersistent(),
            allowsCredentialAccess: false,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
        let operatingSystemMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

        let userAgent = try await page.webView.evaluateJavaScript("navigator.userAgent") as? String

        XCTAssertEqual(
            userAgent?.hasSuffix(
                "Version/\(operatingSystemMajorVersion).0 Safari/604.1"
            ),
            true
        )
        XCTAssertFalse(userAgent?.contains("Crest/") == true)
    }

    func testRealWebKitDownloadCompletesIntoTheAppDownloadsDirectory() async throws {
        let filename = "crest-mobile-\(UUID().uuidString).payload"
        let server = try MobileDownloadHTTPServer(payload: Data("real WebKit mobile download".utf8), filename: filename)
        let port = try await server.start()
        let sourceURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/\(filename)"))
        let destination = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(filename)
        let payload = Data("real WebKit mobile download".utf8)
        let profile = BrowsingProfile()
        let tab = BrowserTab(
            title: "Download fixture",
            url: nil,
            symbol: "arrow.down.circle",
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Download Space",
            symbol: "arrow.down.circle",
            accent: .teal,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let center = BrowserDownloadCenter(
            approveRiskyDownload: { _, _, _ in true },
            approveAutomaticDownload: { _, _, _ in .allowOnce }
        )
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            downloadCenter: center,
            openNewTab: { _ in }
        )
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: destination)
        }

        page.webView.startDownload(using: URLRequest(url: sourceURL)) { download in
            center.start(
                download,
                in: page.webView,
                profileID: profile.id,
                spaceID: space.id,
                spaceName: space.name
            )
        }

        try await waitUntil(timeout: 5) {
            center.items.first?.state == .finished
                || center.items.contains { if case .failed = $0.state { true } else { false } }
        }
        let item = try XCTUnwrap(center.items.first)
        XCTAssertEqual(item.profileID, profile.id)
        XCTAssertEqual(item.filename, filename)
        XCTAssertEqual(item.state, .finished)
        XCTAssertEqual(item.destinationURL, destination)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        await Self.removeDataStore(profile.id)
    }

    func testPrivateHostileWebKitDownloadWaitsForItsSpaceAndCancellationWritesNothing() async throws {
        let filename = "crest-private-\(UUID().uuidString).command"
        let server = try MobileDownloadHTTPServer(
            payload: Data("potentially dangerous private download".utf8),
            filename: filename
        )
        let port = try await server.start()
        let sourceURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/\(filename)"))
        let destination = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(filename)
        let browser = BrowserStore.privateBrowsing()
        let permissionCenter = BrowserSitePermissionCenter()
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            permissionCenter: permissionCenter
        )
        let privateSpace = try XCTUnwrap(browser.selectedSpace)
        let sourceOrigin = try XCTUnwrap(BrowserSiteOrigin(url: sourceURL))
        permissionCenter.setDecision(
            .grantForSession,
            for: .automaticDownloads,
            origin: sourceOrigin,
            in: privateSpace.id
        )
        pages.select(session: browser.session)
        let page = try XCTUnwrap(pages.activePage)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: destination)
            pages.downloadRiskConfirmation.cancelAll()
            pages.closePrivateBrowsingSession(browser.session)
        }

        page.webView.startDownload(using: URLRequest(url: sourceURL)) { download in
            pages.downloadCenter.start(
                download,
                in: page.webView,
                profileID: privateSpace.profile.id,
                spaceID: privateSpace.id,
                spaceName: privateSpace.name
            )
        }

        try await waitUntil(timeout: 5) {
            pages.downloadRiskConfirmation.request != nil
        }
        let request = try XCTUnwrap(pages.downloadRiskConfirmation.request)
        XCTAssertEqual(request.assessment.sanitizedFilename, filename)
        XCTAssertTrue(request.assessment.requiresConfirmation)
        XCTAssertEqual(request.spaceName, "Private")
        XCTAssertEqual(request.sourceLabel, "localhost")
        XCTAssertEqual(pages.downloadCenter.items.first?.state, .awaitingApproval)
        XCTAssertEqual(
            pages.downloadCenter.items.first?.profileID,
            privateSpace.profile.id
        )

        pages.downloadRiskConfirmation.cancel()

        try await waitUntil(timeout: 5) {
            pages.downloadCenter.items.contains {
                if case .canceled = $0.state { return true }
                return false
            }
        }
        XCTAssertEqual(
            pages.downloadCenter.items.first?.state,
            .canceled("Canceled before downloading a potentially dangerous file.")
        )
        XCTAssertNil(pages.downloadCenter.items.first?.destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testDownloadHTTPAuthenticationUsesTheSpaceSessionWithoutSavingOnHTTP() async throws {
        let filename = "crest-auth-\(UUID().uuidString).payload"
        let server = try MobileDownloadHTTPServer(
            payload: Data("authenticated download".utf8),
            filename: filename,
            basicAuthentication: (username: "member", password: "test-secret")
        )
        let port = try await server.start()
        let sourceURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/\(filename)"))
        let destination = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(filename)
        let profile = BrowsingProfile()
        let tab = BrowserTab(title: "Protected download", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Download Space",
            symbol: "arrow.down.circle",
            accent: .teal,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        var prompts: [BrowserHTTPAuthenticationPrompt] = []
        var loadCount = 0
        var saveCount = 0
        let center = BrowserDownloadCenter(
            promptForCredentials: { prompt, requestedSpaceName in
                XCTAssertEqual(requestedSpaceName, space.name)
                prompts.append(prompt)
                return BrowserHTTPAuthenticationPromptResponse(
                    username: "member",
                    password: "test-secret",
                    shouldSave: true
                )
            },
            loadCredential: { _, requestedSpaceID in
                XCTAssertEqual(requestedSpaceID, space.id)
                loadCount += 1
                return nil
            },
            saveCredential: { _, requestedSpaceID in
                XCTAssertEqual(requestedSpaceID, space.id)
                saveCount += 1
            },
            approveRiskyDownload: { _, _, _ in true },
            approveAutomaticDownload: { _, _, _ in .allowOnce }
        )
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            downloadCenter: center,
            openNewTab: { _ in }
        )
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: destination)
        }

        page.webView.startDownload(using: URLRequest(url: sourceURL)) { download in
            center.start(
                download,
                in: page.webView,
                profileID: profile.id,
                spaceID: space.id,
                spaceName: space.name
            )
        }

        try await waitUntil(timeout: 5) {
            center.items.first?.state == .finished
                || center.items.contains { if case .failed = $0.state { true } else { false } }
        }

        XCTAssertEqual(center.items.first?.state, .finished)
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.allowsSaving, false)
        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(saveCount, 0)
        await Self.removeDataStore(profile.id)
    }

    func testFileSelectionPolicyAddsFoldersOnlyForDirectoryInputs() {
        XCTAssertEqual(MobileBrowserFileSelectionPolicy.contentTypes(allowsDirectories: false), [.item])
        XCTAssertEqual(MobileBrowserFileSelectionPolicy.contentTypes(allowsDirectories: true), [.item, .folder])
    }

    func testUnsupportedResponseTypesBecomeDownloads() {
        XCTAssertEqual(
            BrowserNavigationDecider.decidePolicy(canShowMIMEType: false),
            .download
        )
        XCTAssertEqual(
            BrowserNavigationDecider.decidePolicy(canShowMIMEType: true),
            .allow
        )
    }

    func testMobileCommandClickedWebLinksUseNativeBackgroundAndForegroundTabDisposition() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))

        XCTAssertEqual(
            BrowserModifiedLinkDisposition.classify(
                destinationURL: url,
                isUserActivatedLink: true,
                isCommandModified: true,
                isShiftModified: false,
                isMiddleClick: false
            ),
            .backgroundTab(url)
        )
        XCTAssertEqual(
            BrowserModifiedLinkDisposition.classify(
                destinationURL: url,
                isUserActivatedLink: true,
                isCommandModified: true,
                isShiftModified: true,
                isMiddleClick: false
            ),
            .foregroundTab(url)
        )
    }

    func testHTTPAuthenticationPromptsOnlyForBoundedBasicAndDigestChallenges() {
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic,
                isProxy: false,
                previousFailureCount: 0
            ),
            .promptForCredentials
        )
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodHTTPDigest,
                isProxy: false,
                previousFailureCount: BrowserAuthenticationPolicy.maximumCredentialAttempts
            ),
            .cancel
        )
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodServerTrust,
                isProxy: false,
                previousFailureCount: 0
            ),
            .performDefaultHandling
        )
    }

    func testDownloadRecordsRemainProfileScopedAndCanBeClearedIndependently() {
        var ledger = BrowserDownloadLedger()
        let workProfileID = UUID()
        let personalProfileID = UUID()
        let workItemID = ledger.begin(profileID: workProfileID, filename: "work.pdf")
        _ = ledger.begin(profileID: personalProfileID, filename: "personal.pdf")

        ledger.finish(workItemID)
        ledger.remove(workItemID)

        XCTAssertTrue(ledger.items(for: workProfileID).isEmpty)
        XCTAssertEqual(ledger.items(for: personalProfileID).map(\.filename), ["personal.pdf"])
    }

    func testMobileDownloadTransferMovesFromPrivateStagingToTheVisibleRecord() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = root.appendingPathComponent("Staging/source.txt")
        let destination = root.appendingPathComponent("Downloads/report.txt")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("mobile download".utf8).write(to: staging)

        try BrowserDownloadTransfer.finish(from: staging, to: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("mobile download".utf8))
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                throw MobileBrowserInteropTestError.timedOutWaitingForDownload
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func removeDataStore(_ identifier: UUID) async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in continuation.resume() }
        }
    }

    func testUserActivatedPopupAdoptsWebKitsConfigurationIntoANewSelectedTab() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.selectedTab?.id)

        let popupWebView = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        let popupTab = try XCTUnwrap(
            context.store.selectedSpace?.tabs.first { $0.id != openerTabID }
        )
        XCTAssertEqual(popupTab.url, popupURL)
        XCTAssertEqual(context.store.selectedTab?.id, popupTab.id)
        XCTAssertEqual(context.pages.activePage?.tabID, popupTab.id)
        XCTAssertTrue(context.pages.containsResidentPage(for: popupTab.id))
        XCTAssertTrue(
            popupWebView.configuration.userContentController
                === context.opener.webView.configuration.userContentController
        )
    }

    func testAutomaticPopupBridgeBlocksCoalescesAndAllowsOnlyANewAttempt() async throws {
        let context = try makePopupContext()
        let origin = try XCTUnwrap(URL(string: "https://mobile-popups.crest.test/"))
        let siteOrigin = try XCTUnwrap(BrowserSiteOrigin(url: origin))
        context.opener.webView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        context.opener.webView.loadSimulatedRequest(
            URLRequest(url: origin),
            responseHTML: """
                <!doctype html><html><body><script>
                globalThis.results = [];
                globalThis.tryPopup = () => {
                  const result = window.open('about:blank') === null ? 'null' : 'window';
                  globalThis.results.push(result);
                  return result;
                };
                setTimeout(() => {
                  globalThis.tryPopup();
                  globalThis.tryPopup();
                  globalThis.tryPopup();
                }, 100);
                </script></body></html>
                """
        )

        try await waitUntil(timeout: 5) {
            context.opener.blockedPopupState.notice?.status == .blocked
        }
        let blockedResults =
            try await context.opener.webView.callAsyncJavaScript(
                "return globalThis.results.join(',');",
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? String
        XCTAssertEqual(blockedResults, "null,null,null")
        XCTAssertEqual(context.store.selectedSpace?.tabs.count, 1)
        XCTAssertEqual(context.opener.blockedPopupState.indicationRevision, 1)

        context.opener.allowAutomaticPopupsForBlockedSite()

        XCTAssertEqual(
            context.pages.permissionCenter.decision(
                for: .popups,
                origin: siteOrigin,
                in: context.opener.spaceID
            ),
            .grantPersistently
        )
        XCTAssertEqual(
            context.opener.blockedPopupState.notice?.status,
            .allowedAwaitingRetry
        )
        XCTAssertEqual(context.store.selectedSpace?.tabs.count, 1)

        let retryResult =
            try await context.opener.webView.callAsyncJavaScript(
                "return globalThis.tryPopup();",
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? String
        XCTAssertEqual(retryResult, "window")
        try await waitUntil(timeout: 5) {
            context.store.selectedSpace?.tabs.count == 2
        }
        XCTAssertNil(context.opener.blockedPopupState.notice)
        XCTAssertTrue(context.pages.activePage?.wasOpenedAsPopup == true)

        context.pages.reconcile(validTabIDs: [])
    }

    func testAdoptedPopupWebViewIsTheOneRegisteredForItsPopupTab() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()

        let popupWebView = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        let popupPage = try XCTUnwrap(context.pages.activePage)
        XCTAssertTrue(popupPage.webView === popupWebView)
        XCTAssertTrue(popupPage.wasOpenedAsPopup)
        XCTAssertTrue(popupPage.isAwaitingPopupNavigation)
        XCTAssertNil(popupPage.pendingNavigationURL)
        XCTAssertFalse(context.opener.wasOpenedAsPopup)
    }

    func testAdoptedPopupInheritsTheOpenerWebsiteDataStoreAndProfile() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()

        let popupWebView = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        let popupPage = try XCTUnwrap(context.pages.activePage)
        XCTAssertTrue(
            popupWebView.configuration.websiteDataStore
                === context.opener.webView.configuration.websiteDataStore
        )
        XCTAssertEqual(popupPage.spaceID, context.opener.spaceID)
        XCTAssertEqual(popupPage.profileID, context.opener.profileID)
    }

    func testPopupWithoutARequestedURLAdoptsABlankTab() throws {
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.selectedTab?.id)

        _ = try XCTUnwrap(context.requestPopup(url: nil, navigationType: .linkActivated))

        let popupTab = try XCTUnwrap(
            context.store.selectedSpace?.tabs.first { $0.id != openerTabID }
        )
        XCTAssertEqual(popupTab.url, URL(string: "about:blank"))
        XCTAssertFalse(popupTab.isStartPage)
    }

    func testPopupFromATransientPeekPageFallsBackToARoutedTab() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let peekURL = try XCTUnwrap(URL(string: "about:blank"))
        var routedURLs: [URL] = []
        let space = makePopupSpace()
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            popupTabHost: store.popupTabHost,
            openNewTab: { routedURLs.append($0) }
        )
        let lease = try XCTUnwrap(
            pages.makeTransientPageLease(url: peekURL, in: space)
        )
        let peekPage = try XCTUnwrap(lease.page)
        let tabCount = try XCTUnwrap(store.selectedSpace?.tabs.count)

        let popupWebView = peekPage.webView(
            peekPage.webView,
            createWebViewWith: try XCTUnwrap(
                peekPage.webView.configuration.copy() as? WKWebViewConfiguration
            ),
            for: StubPopupNavigationAction(url: popupURL, navigationType: .linkActivated),
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(popupWebView)
        XCTAssertEqual(routedURLs, [popupURL])
        XCTAssertEqual(store.selectedSpace?.tabs.count, tabCount)
    }

    func testClosingAnAdoptedPopupWebViewClosesItsTab() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.selectedTab?.id)

        _ = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )
        let popupPage = try XCTUnwrap(context.pages.activePage)
        let popupTabID = popupPage.tabID

        popupPage.webViewDidClose(popupPage.webView)

        XCTAssertFalse(
            context.store.selectedSpace?.tabs.contains { $0.id == popupTabID } == true
        )
        XCTAssertEqual(
            context.store.selectedSpace?.archivedTabs.last?.tab.id,
            popupTabID
        )
        XCTAssertEqual(context.store.selectedTab?.id, openerTabID)
    }

    func testClosingAPageTheUserOpenedKeepsItsTab() throws {
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.selectedTab?.id)

        context.opener.webViewDidClose(context.opener.webView)

        XCTAssertEqual(context.store.selectedTab?.id, openerTabID)
        XCTAssertTrue(
            context.store.selectedSpace?.tabs.contains { $0.id == openerTabID } == true
        )
    }

    func testPrivatePopupAdoptionStaysInsideThePrivateStore() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let regular = try makePopupContext()
        let privateContext = try makePopupContext(browsingMode: .privateBrowsing)

        let popupWebView = try XCTUnwrap(
            privateContext.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        XCTAssertFalse(popupWebView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(privateContext.store.selectedSpace?.tabs.count, 2)
        XCTAssertEqual(regular.store.selectedSpace?.tabs.count, 1)
        XCTAssertTrue(privateContext.pages.activePage?.wasOpenedAsPopup == true)
        XCTAssertFalse(regular.pages.activePage?.wasOpenedAsPopup == true)
    }

    func testBlockedPopupStateDoesNotLeakIntoAPrivateSession() throws {
        let regular = try makePopupContext()
        let privateContext = try makePopupContext(browsingMode: .privateBrowsing)
        let origin = BrowserSiteOrigin(
            scheme: "https",
            host: "private-popups.example",
            port: 443
        )
        var regularState = regular.opener.blockedPopupState
        XCTAssertTrue(
            regularState.recordBlockedAttempt(
                documentIdentifier: "regular-document",
                origin: origin
            )
        )
        regular.opener.blockedPopupState = regularState

        XCTAssertNotNil(regular.opener.blockedPopupState.notice)
        XCTAssertNil(privateContext.opener.blockedPopupState.notice)
        XCTAssertEqual(
            privateContext.pages.permissionCenter.decision(
                for: .popups,
                origin: origin,
                in: privateContext.opener.spaceID
            ),
            .ask
        )
    }

    func testAPopupToAnotherApplicationsSchemeOpensNoTab() throws {
        let context = try makePopupContext()
        let tabCount = try XCTUnwrap(context.store.selectedSpace?.tabs.count)

        let webView = context.requestPopup(
            url: try XCTUnwrap(URL(string: "mailto:person@example.com")),
            navigationType: .linkActivated
        )

        XCTAssertNil(webView)
        XCTAssertEqual(
            context.store.selectedSpace?.tabs.count,
            tabCount,
            "window.open(\"mailto:…\") must not leave an empty tab behind."
        )
        XCTAssertTrue(context.pages.activePage === context.opener)
    }

    func testAPopupToABlockedSchemeOpensNoTab() throws {
        for address in ["javascript:alert(1)", "file:///etc/passwd"] {
            let context = try makePopupContext()
            let tabCount = try XCTUnwrap(context.store.selectedSpace?.tabs.count)

            let webView = context.requestPopup(
                url: try XCTUnwrap(URL(string: address)),
                navigationType: .linkActivated
            )

            XCTAssertNil(webView, "\(address) must not become a popup window.")
            XCTAssertEqual(context.store.selectedSpace?.tabs.count, tabCount)
        }
    }

    // MARK: - Archived tab state

    func testIdleUnloadingATabArchivesItsSessionStateAndReselectingRestoresIt() async throws {
        let archive = try makeTabStateArchive()
        let firstURL = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        var stateful = BrowserTab(title: "Stateful", url: nil, placement: .current)
        let other = BrowserTab(title: "Other", url: nil, placement: .current)
        let space = makeStateSpace(tabs: [stateful, other], selectedTabID: stateful.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: session)
        let originalPage = try XCTUnwrap(pages.activePage)
        try await load(firstURL, in: originalPage)
        try await load(secondURL, in: originalPage)
        XCTAssertTrue(originalPage.webView.canGoBack)
        // The store keeps a tab's URL in step with its page, so the test does the
        // same before the page is taken away.
        stateful.url = secondURL
        session = BrowserSession(
            spaces: [
                makeStateSpace(
                    id: space.id,
                    profile: space.profile,
                    tabs: [stateful, other],
                    selectedTabID: other.id
                )
            ],
            selectedSpaceID: space.id
        )

        pages.select(session: session)
        pages.unloadPage(for: stateful.id)
        XCTAssertFalse(pages.containsResidentPage(for: stateful.id))
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profile.id, tabID: stateful.id)
        )

        session = BrowserSession(
            spaces: [
                makeStateSpace(
                    id: space.id,
                    profile: space.profile,
                    tabs: [stateful, other],
                    selectedTabID: stateful.id
                )
            ],
            selectedSpaceID: space.id
        )
        pages.select(session: session)
        let restoredPage = try XCTUnwrap(pages.activePage)

        XCTAssertFalse(restoredPage === originalPage)
        XCTAssertEqual(restoredPage.webView.url, secondURL)
        XCTAssertEqual(
            restoredPage.webView.backForwardList.backList.map(\.url),
            [firstURL],
            "A restored tab must come back with the back/forward list it had."
        )

        pages.reconcile(validTabIDs: [])
    }

    func testUnloadingATabArchivesItsSessionState() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Unloadable", url: nil, placement: .current)
        let space = makeStateSpace(tabs: [tab], selectedTabID: tab.id)
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: BrowserSession(spaces: [space], selectedSpaceID: space.id))
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.unloadPage(for: tab.id)
        await archive.flushPendingWrites()

        XCTAssertFalse(pages.containsResidentPage(for: tab.id))
        XCTAssertNotNil(archive.archivedState(profileID: space.profile.id, tabID: tab.id))
    }

    func testClosingAResidentTabArchivesItsHistoryBeforeReconciliationReleasesIt()
        async throws
    {
        let archive = try makeTabStateArchive()
        let firstURL = try XCTUnwrap(
            URL(string: "https://state.crest.test/close-first")
        )
        let secondURL = try XCTUnwrap(
            URL(string: "https://state.crest.test/close-second")
        )
        let stateful = BrowserTab(
            title: "Stateful",
            url: nil,
            placement: .current
        )
        let fallback = BrowserTab(
            title: "Fallback",
            url: nil,
            placement: .current
        )
        let space = makeStateSpace(
            tabs: [stateful, fallback],
            selectedTabID: stateful.id
        )
        var session = BrowserSession(
            spaces: [space],
            selectedSpaceID: space.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: session)
        let originalPage = try XCTUnwrap(pages.activePage)
        try await load(firstURL, in: originalPage)
        try await load(secondURL, in: originalPage)
        XCTAssertTrue(
            session.updateTab(
                url: secondURL,
                title: "Second",
                tabID: stateful.id,
                in: space.id
            )
        )

        session.closeTab(stateful.id, fallbackTabID: fallback.id)
        pages.reconcile(session: session)
        await pages.flushPendingTabStateWrites()

        XCTAssertFalse(pages.containsResidentPage(for: stateful.id))
        XCTAssertNotNil(
            archive.archivedState(
                profileID: space.profile.id,
                tabID: stateful.id
            ),
            "Closing must write the resident interaction state before the session sweep releases the page."
        )

        session.restoreArchivedTab(stateful.id)
        pages.select(session: session)
        let restoredPage = try XCTUnwrap(pages.activePage)

        XCTAssertFalse(restoredPage === originalPage)
        XCTAssertEqual(restoredPage.webView.url, secondURL)
        XCTAssertEqual(
            restoredPage.webView.backForwardList.backList.map(\.url),
            [firstURL]
        )

        pages.reconcile(validTabIDs: [])
    }

    func testStateWebKitRefusesFallsBackToAnOrdinaryLoad() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Corrupt", url: url, placement: .current)
        let space = makeStateSpace(tabs: [tab], selectedTabID: tab.id)
        // Correctly framed and stamped for this build, so only WebKit can refuse it.
        archive.archive(
            interactionState: Data((0..<1024).map { _ in UInt8.random(in: 0...255) }),
            url: url,
            profileID: space.profile.id,
            tabID: tab.id
        )
        await archive.flushPendingWrites()
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: BrowserSession(spaces: [space], selectedSpaceID: space.id))
        let page = try XCTUnwrap(pages.activePage)

        XCTAssertTrue(page.webView.backForwardList.backList.isEmpty)
        XCTAssertEqual(
            page.pendingNavigationURL ?? page.webView.url,
            url,
            "Refused state must leave a plain load of the tab's own URL behind."
        )

        pages.reconcile(validTabIDs: [])
    }

    func testPrivateBrowsingArchivesNoTabStateEvenWhenGivenAnArchive() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Private", url: nil, placement: .current)
        let space = makeStateSpace(tabs: [tab], selectedTabID: tab.id)
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            tabStateArchive: archive
        )

        pages.select(session: BrowserSession(spaces: [space], selectedSpaceID: space.id))
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.archiveResidentTabStates()
        pages.unloadPage(for: tab.id)
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: space.profile.id, tabID: tab.id),
            "Private browsing must leave nothing on disk to restore."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: archive.rootDirectory.path),
            "A private store must not even create the archive's directory."
        )
    }

    func testDeletingASpaceRemovesItsArchivedTabStates() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Deleted", url: nil, placement: .current)
        let space = makeStateSpace(tabs: [tab], selectedTabID: tab.id)
        let survivingProfileID = UUID()
        let survivingTabID = TabID()
        archive.archive(
            interactionState: Data("other space".utf8),
            url: url,
            profileID: survivingProfileID,
            tabID: survivingTabID
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            websiteDataStoreRemover: MobileRecordingWebsiteDataStoreRemover(),
            tabStateArchive: archive
        )

        pages.select(session: BrowserSession(spaces: [space], selectedSpaceID: space.id))
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.unloadPage(for: tab.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(archive.archivedState(profileID: space.profile.id, tabID: tab.id))

        try await pages.deleteData(for: space)
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: space.profile.id, tabID: tab.id),
            "Deleting a Space must take its archived session state with it."
        )
        XCTAssertNotNil(
            archive.archivedState(profileID: survivingProfileID, tabID: survivingTabID),
            "Space deletion must not reach another Space's state."
        )
    }

    // MARK: - Idle unloading

    func testIdleUnloadArchivesTheTabStateItTakesAway() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let stateful = BrowserTab(title: "Stateful", url: nil, placement: .current)
        let other = BrowserTab(title: "Other", url: nil, placement: .current)
        let space = makeStateSpace(tabs: [stateful, other], selectedTabID: stateful.id)
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: BrowserSession(spaces: [space], selectedSpaceID: space.id))
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.select(
            session: BrowserSession(
                spaces: [
                    makeStateSpace(
                        id: space.id,
                        profile: space.profile,
                        tabs: [stateful, other],
                        selectedTabID: other.id
                    )
                ],
                selectedSpaceID: space.id
            )
        )
        XCTAssertTrue(pages.containsResidentPage(for: stateful.id))

        pages.unloadPage(for: stateful.id)
        await archive.flushPendingWrites()

        XCTAssertFalse(pages.containsResidentPage(for: stateful.id))
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profile.id, tabID: stateful.id),
            "Idle unloading must preserve the tab's WebKit session state."
        )

        pages.reconcile(validTabIDs: [])
    }

    func testPrivateIdleUnloadArchivesNothing() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let stateful = BrowserTab(title: "Stateful", url: nil, placement: .current)
        let other = BrowserTab(title: "Other", url: nil, placement: .current)
        let space = makeStateSpace(tabs: [stateful, other], selectedTabID: stateful.id)
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            tabStateArchive: archive
        )

        pages.select(session: BrowserSession(spaces: [space], selectedSpaceID: space.id))
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.select(
            session: BrowserSession(
                spaces: [
                    makeStateSpace(
                        id: space.id,
                        profile: space.profile,
                        tabs: [stateful, other],
                        selectedTabID: other.id
                    )
                ],
                selectedSpaceID: space.id
            )
        )

        pages.unloadPage(for: stateful.id)
        await archive.flushPendingWrites()

        XCTAssertFalse(pages.containsResidentPage(for: stateful.id))
        XCTAssertNil(
            archive.archivedState(profileID: space.profile.id, tabID: stateful.id),
            "A private page unloaded after idling must leave nothing behind."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: archive.rootDirectory.path),
            "A private store must not create an archive while idly unloading."
        )
    }

    func testIdleUnloadEvictsAnAdoptedPopupLikeAnyOtherResidentPage() async throws {
        let archive = try makeTabStateArchive()
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext(tabStateArchive: archive)
        let openerTabID = try XCTUnwrap(context.store.selectedSpace?.tabs.first?.id)

        _ = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )
        let popupPage = try XCTUnwrap(context.pages.activePage)
        let popupTabID = popupPage.tabID
        context.store.selectTab(openerTabID)
        context.pages.select(session: context.store.session)
        XCTAssertTrue(context.pages.containsResidentPage(for: popupTabID))

        context.pages.unloadPage(for: popupTabID)
        await archive.flushPendingWrites()

        XCTAssertTrue(popupPage.wasOpenedAsPopup)
        XCTAssertFalse(
            context.pages.containsResidentPage(for: popupTabID),
            "An adopted popup follows the same idle lifetime as any resident page."
        )
        XCTAssertEqual(context.pages.activePage?.tabID, openerTabID)
        XCTAssertNil(
            archive.archivedState(
                profileID: popupPage.profileID,
                tabID: popupTabID
            ),
            "WebKit drives an adopted popup's window, so Crest never archives it."
        )

        context.pages.reconcile(validTabIDs: [])
    }

    // MARK: - Relocking a protected Space

    func testRelockingAProtectedSpacePurgesTheStateItsUnloadsLeftBehind() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secret = BrowserTab(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeStateSpace(
            tabs: [secret],
            selectedTabID: secret.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = BrowserTab(title: "Open", url: nil, placement: .current)
        let openSpace = makeStateSpace(tabs: [openTab], selectedTabID: openTab.id)
        var session = BrowserSession(
            spaces: [protectedSpace, openSpace],
            selectedSpaceID: openSpace.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: session)
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.unloadPage(for: openTab.id)
        session.selectSpace(protectedSpace.id)
        pages.select(session: session)
        try await load(url, in: try XCTUnwrap(pages.activePage))
        // The unload that leaves the residue: the page is gone from memory
        // long before the Space relocks, and its state is already on disk.
        pages.unloadPage(for: secret.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(
                profileID: protectedSpace.profile.id,
                tabID: secret.id
            )
        )

        pages.relockProtectedSpace(protectedSpace)
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(
                profileID: protectedSpace.profile.id,
                tabID: secret.id
            ),
            "A relocked Space must leave no page state at rest."
        )
        XCTAssertNotNil(
            archive.archivedState(
                profileID: openSpace.profile.id,
                tabID: openTab.id
            ),
            "Relocking one Space must not reach another Space's state."
        )
    }

    func testRelockingAProtectedSpaceReleasesOnlyItsOwnResidentPages() throws {
        let secret = BrowserTab(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeStateSpace(
            tabs: [secret],
            selectedTabID: secret.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = BrowserTab(title: "Open", url: nil, placement: .current)
        let openSpace = makeStateSpace(tabs: [openTab], selectedTabID: openTab.id)
        var session = BrowserSession(
            spaces: [protectedSpace, openSpace],
            selectedSpaceID: openSpace.id
        )
        let pages = MobileBrowserPageStore()

        pages.select(session: session)
        session.selectSpace(protectedSpace.id)
        pages.select(session: session)
        XCTAssertTrue(pages.containsResidentPage(for: secret.id))

        pages.relockProtectedSpace(protectedSpace)

        XCTAssertFalse(pages.containsResidentPage(for: secret.id))
        XCTAssertTrue(pages.containsResidentPage(for: openTab.id))
    }

    func testAPurgedTabComesBackWithAPlainLoadAfterTheSpaceUnlocks() async throws {
        let archive = try makeTabStateArchive()
        let firstURL = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        var secret = BrowserTab(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeStateSpace(
            tabs: [secret],
            selectedTabID: secret.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        var session = BrowserSession(
            spaces: [protectedSpace],
            selectedSpaceID: protectedSpace.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: session)
        let originalPage = try XCTUnwrap(pages.activePage)
        try await load(firstURL, in: originalPage)
        try await load(secondURL, in: originalPage)
        XCTAssertTrue(originalPage.webView.canGoBack)
        secret.url = secondURL
        pages.unloadPage(for: secret.id)
        pages.relockProtectedSpace(protectedSpace)
        await archive.flushPendingWrites()

        // What the next unlock does: the tab is selected again with no state to
        // restore into.
        session = BrowserSession(
            spaces: [
                makeStateSpace(
                    id: protectedSpace.id,
                    profile: protectedSpace.profile,
                    tabs: [secret],
                    selectedTabID: secret.id,
                    accessPolicy: .deviceOwnerAuthentication
                )
            ],
            selectedSpaceID: protectedSpace.id
        )
        pages.select(session: session)
        let restoredPage = try XCTUnwrap(pages.activePage)

        XCTAssertFalse(restoredPage === originalPage)
        XCTAssertEqual(
            restoredPage.pendingNavigationURL ?? restoredPage.webView.url,
            secondURL,
            "A purged tab falls back to a plain load of its own URL."
        )
        XCTAssertTrue(
            restoredPage.webView.backForwardList.backList.isEmpty,
            "The back/forward list the purge took away must not come back."
        )

        pages.reconcile(validTabIDs: [])
    }

    func testRelockingAnOpenSpaceKeepsItsArchivedTabState() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Ordinary", url: nil, placement: .current)
        let openSpace = makeStateSpace(tabs: [tab], selectedTabID: tab.id)
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(
            session: BrowserSession(spaces: [openSpace], selectedSpaceID: openSpace.id)
        )
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.unloadPage(for: tab.id)
        await archive.flushPendingWrites()

        // The lock sweep hands over every Space it walks; an unprotected one has
        // nothing to relock, so its state has to survive the call.
        pages.relockProtectedSpace(openSpace)
        await archive.flushPendingWrites()

        XCTAssertNotNil(
            archive.archivedState(profileID: openSpace.profile.id, tabID: tab.id),
            "An open Space is never relocked, so nothing of its is purged."
        )
    }

    func testIdleUnloadInAnUnlockedProtectedSpaceStillArchives() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let first = BrowserTab(title: "First", url: nil, placement: .current)
        let second = BrowserTab(title: "Second", url: nil, placement: .current)
        let protectedSpace = makeStateSpace(
            tabs: [first, second],
            selectedTabID: first.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        var session = BrowserSession(
            spaces: [protectedSpace],
            selectedSpaceID: protectedSpace.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: session)
        try await load(url, in: try XCTUnwrap(pages.activePage))
        // Idle unloading, not a relock: an unlocked protected Space archives like
        // any other, which is what makes the relock purge worth having.
        session = BrowserSession(
            spaces: [
                makeStateSpace(
                    id: protectedSpace.id,
                    profile: protectedSpace.profile,
                    tabs: [first, second],
                    selectedTabID: second.id,
                    accessPolicy: .deviceOwnerAuthentication
                )
            ],
            selectedSpaceID: protectedSpace.id
        )
        pages.select(session: session)
        pages.unloadPage(for: first.id)
        await archive.flushPendingWrites()

        XCTAssertFalse(pages.containsResidentPage(for: first.id))
        XCTAssertNotNil(
            archive.archivedState(
                profileID: protectedSpace.profile.id,
                tabID: first.id
            )
        )

        pages.reconcile(validTabIDs: [])
    }

    /// Loads `url` as a simulated response so a back/forward entry exists without
    /// a network fixture, and waits for WebKit to commit it.
    private func load(_ url: URL, in page: MobileBrowserPage) async throws {
        page.webView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        page.webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: """
                <!doctype html><html><body style="height: 4000px">\(url.path)</body></html>
                """
        )
        for attempt in 0..<200 {
            if page.webView.url == url, !page.webView.isLoading {
                return
            }
            if attempt < 199 {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        XCTFail("Timed out loading \(url).")
    }

    private func makeTabStateArchive() throws -> BrowserTabStateArchive {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "crest-mobile-tab-state-\(UUID().uuidString)",
                isDirectory: true
            )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return BrowserTabStateArchive(rootDirectory: root)
    }

    private func makeStateSpace(
        id: SpaceID = SpaceID(),
        profile: BrowsingProfile = BrowsingProfile(),
        tabs: [BrowserTab],
        selectedTabID: TabID,
        accessPolicy: BrowserSpaceAccessPolicy = .open
    ) -> BrowserSpace {
        BrowserSpace(
            id: id,
            profile: profile,
            name: "State",
            symbol: "clock.arrow.circlepath",
            accent: .teal,
            folders: [],
            tabs: tabs,
            accessPolicy: accessPolicy,
            selectedTabID: selectedTabID
        )
    }

    private func makePopupContext(
        browsingMode: BrowserBrowsingMode = .standard,
        tabStateArchive: (any BrowserTabStateArchiving)? = nil
    ) throws -> MobilePopupAdoptionContext {
        let space = makePopupSpace()
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: tabStateArchive == nil,
            tabStateArchive: tabStateArchive,
            popupTabHost: store.popupTabHost
        )
        pages.select(session: store.session)
        return MobilePopupAdoptionContext(
            store: store,
            pages: pages,
            opener: try XCTUnwrap(pages.activePage)
        )
    }

    /// A start-page opener keeps the fixture offline: a resident page loads its
    /// tab's URL as soon as it is built.
    private func makePopupSpace() -> BrowserSpace {
        let openerTab = BrowserTab(title: "Opener", url: nil, placement: .current)
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Popups",
            symbol: "macwindow.on.rectangle",
            accent: .teal,
            folders: [],
            tabs: [openerTab],
            selectedTabID: openerTab.id
        )
    }
}

/// Stands in for WebKit's persistent-store removal so a Space can be deleted in a
/// test without touching the simulator's real WebKit data.
@MainActor
private final class MobileRecordingWebsiteDataStoreRemover:
    BrowserWebsiteDataStoreRemoving
{
    private(set) var removedProfileIDs: [UUID] = []

    func removePersistentDataStore(for profile: BrowsingProfile) async throws {
        removedProfileIDs.append(profile.id)
    }
}

/// One opener page, its store, and the store that owns their tabs, so popup tests
/// drive the real `WKUIDelegate` entry point instead of the adoption API.
@MainActor
private struct MobilePopupAdoptionContext {
    let store: BrowserStore
    let pages: MobileBrowserPageStore
    let opener: MobileBrowserPage

    /// Hands the opener a configuration copied from its own, which is what WebKit
    /// does before calling `createWebViewWith`.
    func requestPopup(url: URL?, navigationType: WKNavigationType) -> WKWebView? {
        guard
            let configuration = opener.webView.configuration
                .copy() as? WKWebViewConfiguration
        else { return nil }
        return opener.webView(
            opener.webView,
            createWebViewWith: configuration,
            for: StubPopupNavigationAction(url: url, navigationType: navigationType),
            windowFeatures: WKWindowFeatures()
        )
    }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so popup tests
/// stand in for the one WebKit hands to `createWebViewWith`: no target frame and
/// a navigation type that selects the popup trigger under test.
private final class StubPopupNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest
    private let stubNavigationType: WKNavigationType

    init(url: URL?, navigationType: WKNavigationType) {
        // `window.open()` without a destination reaches WebKit as a request
        // without a URL, which a stub can only reproduce by clearing it.
        var request = URLRequest(url: URL(fileURLWithPath: "/"))
        request.url = url
        stubRequest = request
        stubNavigationType = navigationType
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { stubNavigationType }
    override var targetFrame: WKFrameInfo? { nil }
    var browserSourceOrigin: BrowserSiteOrigin? { nil }
}

private enum MobileBrowserInteropTestError: Error {
    case timedOutWaitingForDownload
    case listenerFailed
}

private final class MobileDownloadHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.pauldavis.crest.tests.mobile-download")
    private let responseData: Data
    private let unauthorizedResponseData: Data
    private let requiredAuthorizationHeader: String?

    init(
        payload: Data,
        filename: String,
        basicAuthentication: (username: String, password: String)? = nil
    ) throws {
        listener = try NWListener(using: .tcp, on: .any)
        let header = """
            HTTP/1.1 200 OK\r
            Content-Type: application/octet-stream\r
            Content-Disposition: attachment; filename="\(filename)"\r
            Content-Length: \(payload.count)\r
            Connection: close\r
            \r

            """
        responseData = Data(header.utf8) + payload
        unauthorizedResponseData = Data(
            """
            HTTP/1.1 401 Unauthorized\r
            WWW-Authenticate: Basic realm="Crest Tests"\r
            Content-Length: 0\r
            Connection: close\r
            \r

            """.utf8
        )
        requiredAuthorizationHeader = basicAuthentication.map {
            let encoded = Data("\($0.username):\($0.password)".utf8).base64EncodedString()
            return "authorization: basic \(encoded)".lowercased()
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: MobileBrowserInteropTestError.listenerFailed)
                        return
                    }
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: port.rawValue)
                case .failed:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: MobileBrowserInteropTestError.listenerFailed)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard state == .ready, let self, let connection else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) {
                [weak self, weak connection] data, _, _, error in
                guard let self, let connection, data != nil, error == nil else {
                    connection?.cancel()
                    return
                }
                let request = data.flatMap { String(data: $0, encoding: .utf8) }?.lowercased()
                let response =
                    requiredAuthorizationHeader.map {
                        request?.contains($0) == true ? responseData : unauthorizedResponseData
                    } ?? responseData
                connection.send(
                    content: response,
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in connection.cancel() }
                )
            }
        }
        connection.start(queue: queue)
    }
}

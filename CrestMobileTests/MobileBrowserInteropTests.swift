import Foundation
import Network
import UIKit
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
            tabs: [tab]
        )
        let browser = BrowserStore.hostingPages(BrowserSession(spaces: [space]))
        let page = try XCTUnwrap(
            browser.openPage(in: space.id, for: tab.id) { corePage in
                MobileBrowserPage(
                    corePage: corePage,
                    tab: tab,
                    space: space,
                    websiteDataStore: .nonPersistent(),
                    allowsCredentialAccess: false,
                    loadsInitialURL: false,
                    openNewTab: { _ in }
                )
            }?.built as? MobileBrowserPage
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
            tabs: [tab]
        )
        let center = BrowserDownloadCenter(
            approveRiskyDownload: { _, _, _, _ in true }
        )
        let browser = BrowserStore.hostingPages(BrowserSession(spaces: [space]))
        let page = try XCTUnwrap(
            browser.openPage(in: space.id, for: tab.id) { corePage in
                MobileBrowserPage(
                    corePage: corePage,
                    tab: tab,
                    space: space,
                    downloadCenter: center,
                    openNewTab: { _ in }
                )
            }?.built as? MobileBrowserPage
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
            center.items.first?.phase == .finished
                || center.items.contains { if case .failed = $0.phase { true } else { false } }
        }
        let item = try XCTUnwrap(center.items.first)
        XCTAssertEqual(item.profileID, profile.id)
        XCTAssertEqual(item.filename, filename)
        XCTAssertEqual(item.phase, .finished)
        XCTAssertEqual(item.destinationURL, destination)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        await Self.removeDataStore(profile.id)
    }

    func testPrivateDisguisedExecutableDownloadWaitsForItsSpaceAndCancellationWritesNothing() async throws {
        let filename = "crest-private-\(UUID().uuidString).jpg"
        let server = try MobileDownloadHTTPServer(
            payload: Data("potentially dangerous private download".utf8),
            filename: filename,
            mimeType: "application/x-mach-binary"
        )
        let port = try await server.start()
        let sourceURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/\(filename)"))
        let destination = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(filename)
        let browser = BrowserStore.privateBrowsing(core: .hostingPages())
        let permissionCenter = BrowserSitePermissionCenter()
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: .privateBrowsing,
            permissionCenter: permissionCenter
        )
        let privateSpace = try XCTUnwrap(browser.selectedSpace)
        let sourceOrigin = try XCTUnwrap(SiteOrigin(url: sourceURL))
        permissionCenter.setDecision(
            .grantForSession,
            for: .automaticDownloads,
            origin: sourceOrigin,
            in: privateSpace.id
        )
        pages.select(session: browser.presented)
        let page = try XCTUnwrap(pages.activePage)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: destination)
            pages.downloadRiskConfirmation.cancelAll()
            pages.closePrivateBrowsingSession(browser.session)
        }

        // User initiation bypasses the extra prompt for ordinary installers.
        // An executable disguised as an image still requires confirmation.
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
        XCTAssertTrue(request.assessment.reasons.contains(.dangerousTypeMismatch))
        XCTAssertEqual(request.spaceName, "Private")
        XCTAssertEqual(request.sourceLabel, "localhost")
        XCTAssertEqual(pages.downloadCenter.items.first?.phase, .awaitingApproval)
        XCTAssertEqual(
            pages.downloadCenter.items.first?.profileID,
            privateSpace.profile.id
        )

        pages.downloadRiskConfirmation.cancel()

        try await waitUntil(timeout: 5) {
            pages.downloadCenter.items.contains {
                if case .canceled = $0.phase { return true }
                return false
            }
        }
        XCTAssertEqual(pages.downloadCenter.items.first?.phase, .canceled)
        XCTAssertEqual(
            pages.downloadCenter.items.first?.message,
            "Canceled before downloading a potentially dangerous file."
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
            tabs: [tab]
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
            approveRiskyDownload: { _, _, _, _ in true }
        )
        let browser = BrowserStore.hostingPages(BrowserSession(spaces: [space]))
        let page = try XCTUnwrap(
            browser.openPage(in: space.id, for: tab.id) { corePage in
                MobileBrowserPage(
                    corePage: corePage,
                    tab: tab,
                    space: space,
                    downloadCenter: center,
                    openNewTab: { _ in }
                )
            }?.built as? MobileBrowserPage
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
            center.items.first?.phase == .finished
                || center.items.contains { if case .failed = $0.phase { true } else { false } }
        }

        XCTAssertEqual(center.items.first?.phase, .finished)
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.allowsSaving, false)
        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(saveCount, 0)
        await Self.removeDataStore(profile.id)
    }

    func testDisplayableInlineDirectVideoUsesMobilePlaybackDocument() throws {
        let url = try XCTUnwrap(
            URL(string: "https://media.example/watch?id=mobile&quality=source")
        )
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "video/mp4",
                    "Content-Disposition": "inline",
                ]
            )
        )

        let navigation = try XCTUnwrap(
            BrowserDirectMediaNavigation.classify(
                canShowMIMEType: true,
                isForMainFrame: true,
                response: response
            )
        )

        XCTAssertEqual(navigation.url, url)
        XCTAssertEqual(navigation.kind, .video)
        XCTAssertTrue(navigation.responseHTML.contains("playsinline"))
        XCTAssertTrue(
            navigation.responseHTML.contains(
                "https://media.example/watch?id=mobile&amp;quality=source"
            )
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
        condition: @escaping @MainActor () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try await !condition() {
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

    func testNativeWindowFocusUsesTheSharedChoiceForCommandMiddleClickAndShift() {
        for focus in [false, true] {
            for shift in [false, true] {
                for middle in [false, true] {
                    var preferences = BrowserLinkPreferences.default
                    preferences.focusesNewTabsOpenedFromLinks = focus
                    var flags: UIKeyModifierFlags = middle ? [] : .command
                    if shift { flags.insert(.shift) }
                    let action = StubPopupNavigationAction(
                        url: nil, navigationType: .other, modifierFlags: flags,
                        buttonNumber: middle ? UIEvent.ButtonMask(rawValue: 1 << 2) : []
                    )
                    XCTAssertEqual(action.selectsOpenedLink(using: preferences), focus != shift)
                }
            }
        }
    }

    func testBackgroundNativeWindowUpdatesItsOwnTabAndBecomesPressureEligibleAfterLoading() async throws {
        let saved = BrowserLinkPreferenceStore.shared.preferences
        defer { BrowserLinkPreferenceStore.shared.update { $0 = saved } }
        BrowserLinkPreferenceStore.shared.focusesNewTabsOpenedFromLinks = false
        let context = try makePopupContext()
        let sourceID = context.store.selectedTab?.id
        let url = try XCTUnwrap(URL(string: "https://example.com/research"))
        let popup = try XCTUnwrap(
            context.opener.webView(
                context.opener.webView,
                createWebViewWith: context.opener.webView.configuration,
                for: StubPopupNavigationAction(url: url, navigationType: .other, modifierFlags: .command),
                windowFeatures: WKWindowFeatures()
            ))
        let tabID = try XCTUnwrap(context.store.selectedSpace?.tabs.first { $0.id != sourceID }?.id)
        XCTAssertEqual(context.store.selectedTab?.id, sourceID)
        XCTAssertTrue(context.pages.activePage === context.opener)
        context.pages.handleMemoryPressure(.critical, at: Date())
        await context.pages.waitForPendingMemoryPressureResponse()
        XCTAssertTrue(context.pages.containsResidentPage(for: tabID))

        popup.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<title>Background ready</title><p>Ready</p>")
        try await waitUntil(timeout: 5) {
            context.store.selectedSpace?.tabs.first { $0.id == tabID }?.title == "Background ready"
                && context.store.selectedSpace?.history.contains { $0.url == url } == true
        }
        XCTAssertEqual(context.store.selectedTab?.id, sourceID)
        context.pages.handleMemoryPressure(.critical, at: Date().addingTimeInterval(5))
        await context.pages.waitForPendingMemoryPressureResponse()
        XCTAssertFalse(context.pages.containsResidentPage(for: tabID))
        XCTAssertTrue(context.pages.activePage === context.opener)
    }

    func testAutomaticPopupBridgeBlocksCoalescesAndAllowsOnlyANewAttempt() async throws {
        let context = try makePopupContext()
        let origin = try XCTUnwrap(URL(string: "https://mobile-popups.crest.test/"))
        let siteOrigin = try XCTUnwrap(SiteOrigin(url: origin))
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

        // Observe the fixture's attempts before checking the native notice.
        // A native-only poll leaves this unmounted page's timers suspended.
        try await waitUntil(timeout: 5) {
            (try? await context.opener.webView.evaluateJavaScript("globalThis.results?.length")) as? Int == 3
        }
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
        XCTAssertNil(popupPage.live.pendingNavigationURL)
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
        let store = BrowserStore.hostingPages(
            BrowserSession(spaces: [space]),
            showing: space.id,
            tabs: shownTabs(in: [space])
        )
        let pages = MobileBrowserPageStore(
            browser: store,
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
        let origin = SiteOrigin(
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
        let space = makeStateSpace(tabs: [stateful, other])
        var session = presented([space], showing: space.id)
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(session.session),
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
        session = presented([
                makeStateSpace(
                    id: space.id,
                    profile: space.profile,
                    tabs: [stateful, other]
                )
            ], showing: space.id, tabs: [space.id: other.id])

        pages.select(session: session)
        pages.unloadPage(for: stateful.id)
        XCTAssertFalse(pages.containsResidentPage(for: stateful.id))
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profile.id, tabID: stateful.id)
        )

        session = presented([
                makeStateSpace(
                    id: space.id,
                    profile: space.profile,
                    tabs: [stateful, other]
                )
            ], showing: space.id, tabs: [space.id: stateful.id])
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
        let space = makeStateSpace(tabs: [tab])
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(BrowserSession(spaces: [space])),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: presented([space], showing: space.id))
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
            tabs: [stateful, fallback]
        )
        var session = presented([space], showing: space.id)
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(session.session),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: session)
        let originalPage = try XCTUnwrap(pages.activePage)
        try await load(firstURL, in: originalPage)
        try await load(secondURL, in: originalPage)
        var spaces = session.spaces
        spaces[0].tabs[0].url = secondURL
        spaces[0].tabs[0].title = "Second"

        // What the core does on close: the tab moves to the Space's archive.
        let closed = spaces[0].tabs.removeFirst()
        spaces[0].archivedTabs.append(ArchivedTab(tab: closed, archivedAt: .now, reason: .closed))
        session = presented(spaces, showing: space.id, tabs: [space.id: fallback.id])
        pages.reconcile(session: session.session)
        await pages.flushPendingTabStateWrites()

        XCTAssertFalse(pages.containsResidentPage(for: stateful.id))
        XCTAssertNotNil(
            archive.archivedState(
                profileID: space.profile.id,
                tabID: stateful.id
            ),
            "Closing must write the resident interaction state before the session sweep releases the page."
        )

        spaces[0].tabs.append(spaces[0].archivedTabs.removeLast().tab)
        session = presented(spaces, showing: space.id, tabs: [space.id: stateful.id])
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
        let space = makeStateSpace(tabs: [tab])
        // Correctly framed and stamped for this build, so only WebKit can refuse it.
        archive.archive(
            interactionState: Data((0..<1024).map { _ in UInt8.random(in: 0...255) }),
            url: url,
            profileID: space.profile.id,
            tabID: tab.id
        )
        await archive.flushPendingWrites()
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(BrowserSession(spaces: [space])),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: presented([space], showing: space.id))
        let page = try XCTUnwrap(pages.activePage)

        XCTAssertTrue(page.webView.backForwardList.backList.isEmpty)
        XCTAssertEqual(
            page.live.pendingNavigationURL ?? page.webView.url,
            url,
            "Refused state must leave a plain load of the tab's own URL behind."
        )

        pages.reconcile(validTabIDs: [])
    }

    func testPrivateBrowsingArchivesNoTabStateEvenWhenGivenAnArchive() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Private", url: nil, placement: .current)
        let space = makeStateSpace(tabs: [tab])
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(BrowserSession(spaces: [space]), browsingMode: .privateBrowsing),
            browsingMode: .privateBrowsing,
            tabStateArchive: archive
        )

        pages.select(session: presented([space], showing: space.id))
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
        let space = makeStateSpace(tabs: [tab])
        let survivingProfileID = UUID()
        let survivingTabID = TabID()
        archive.archive(
            interactionState: Data("other space".utf8),
            url: url,
            profileID: survivingProfileID,
            tabID: survivingTabID
        )
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(BrowserSession(spaces: [space])),
            usesEphemeralWebsiteDataStores: false,
            profileRemover: MobileRecordingWebsiteDataStoreRemover(),
            tabStateArchive: archive
        )

        pages.select(session: presented([space], showing: space.id))
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
        let space = makeStateSpace(tabs: [stateful, other])
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(BrowserSession(spaces: [space])),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: presented([space], showing: space.id))
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.select(
            session: presented([
                    makeStateSpace(
                        id: space.id,
                        profile: space.profile,
                        tabs: [stateful, other]
                    )
                ], showing: space.id, tabs: [space.id: other.id])
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
        let space = makeStateSpace(tabs: [stateful, other])
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(BrowserSession(spaces: [space]), browsingMode: .privateBrowsing),
            browsingMode: .privateBrowsing,
            tabStateArchive: archive
        )

        pages.select(session: presented([space], showing: space.id))
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.select(
            session: presented([
                    makeStateSpace(
                        id: space.id,
                        profile: space.profile,
                        tabs: [stateful, other]
                    )
                ], showing: space.id, tabs: [space.id: other.id])
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
        context.pages.select(session: context.store.presented)
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
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = BrowserTab(title: "Open", url: nil, placement: .current)
        let openSpace = makeStateSpace(tabs: [openTab])
        var session = presented([protectedSpace, openSpace], showing: openSpace.id)
        let browser = BrowserStore.hostingPages(session.session)
        browser.unlockForTesting(protectedSpace)
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: session)
        try await load(url, in: try XCTUnwrap(pages.activePage))
        pages.unloadPage(for: openTab.id)
        session = presented(session.spaces, showing: protectedSpace.id, tabs: shownTabs(of: session))
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

    func testRelockingAProtectedSpacePreservesItsResidentPageAndOtherPresentation() throws {
        let secret = BrowserTab(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeStateSpace(
            tabs: [secret],
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = BrowserTab(title: "Open", url: nil, placement: .current)
        let openSpace = makeStateSpace(tabs: [openTab])
        var session = presented([protectedSpace, openSpace], showing: openSpace.id)
        let browser = BrowserStore.hostingPages(session.session)
        browser.unlockForTesting(protectedSpace)
        let pages = MobileBrowserPageStore(browser: browser)

        pages.select(session: session)
        session = presented(session.spaces, showing: protectedSpace.id, tabs: shownTabs(of: session))
        pages.select(session: session)
        let secretPage = try XCTUnwrap(pages.activePage)
        XCTAssertTrue(pages.containsResidentPage(for: secret.id))

        pages.relockProtectedSpace(protectedSpace)

        XCTAssertNil(pages.activePage)
        XCTAssertTrue(pages.presentedTabIDs.isEmpty)
        XCTAssertTrue(pages.containsResidentPage(for: secret.id))
        XCTAssertTrue(pages.containsResidentPage(for: openTab.id))

        pages.select(session: session)
        XCTAssertTrue(pages.activePage === secretPage)
        session = presented(session.spaces, showing: openSpace.id, tabs: shownTabs(of: session))
        pages.select(session: session)
        let openPage = pages.activePage
        pages.relockProtectedSpace(protectedSpace)
        XCTAssertTrue(pages.activePage === openPage)
        XCTAssertEqual(pages.presentedTabIDs, [openTab.id])
    }

    func testRepeatedRelockingPreservesLoadedPageScrollFormsAndHistory() async throws {
        let firstURL = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        let tab = BrowserTab(title: "Secret", url: nil, placement: .current)
        let space = makeStateSpace(
            tabs: [tab], accessPolicy: .deviceOwnerAuthentication
        )
        var session = presented([space], showing: space.id)
        let browser = BrowserStore.hostingPages(session.session)
        browser.unlockForTesting(space)
        let pages = MobileBrowserPageStore(browser: browser)
        pages.select(session: session)
        let original = try XCTUnwrap(pages.activePage)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let controller = UIViewController()
        let host = MobileBrowserWebHostView(frame: window.bounds)
        controller.view = host
        window.rootViewController = controller
        window.isHidden = false
        host.attach(original.webView)
        host.layoutIfNeeded()
        defer {
            host.detach(stopsLoading: false)
            window.isHidden = true
        }
        try await load(firstURL, in: original)
        try await load(secondURL, in: original)
        // A JavaScript scroll can precede UIKit's first rendered layout. Wait
        // for the real scrolling surface before exercising detach/reattach.
        try await waitUntil(timeout: 5) {
            original.webView.scrollView.contentSize.height > original.webView.bounds.height
        }
        _ = try await original.webView.evaluateJavaScript(
            "document.body.innerHTML += '<input id=note>'; document.getElementById('note').value = 'draft'; window.scrollTo(0, 850);"
        )
        try await waitUntil(timeout: 5) {
            let scroll = (try? await original.webView.evaluateJavaScript("window.scrollY")) as? Double ?? 0
            return scroll > 0 && original.webView.scrollView.contentOffset.y > 0
        }
        let scrollValue = try await original.webView.evaluateJavaScript("window.scrollY")
        let scroll = try XCTUnwrap(scrollValue as? Double)
        XCTAssertGreaterThan(scroll, 0)
        var spaces = session.spaces
        spaces[0].tabs[0].url = secondURL
        session = presented(spaces, showing: space.id, tabs: shownTabs(of: session))

        for _ in 0..<3 {
            pages.relockProtectedSpace(space)
            host.detach(stopsLoading: false)
            XCTAssertNil(pages.activePage)
            XCTAssertTrue(pages.presentedTabIDs.isEmpty)
            pages.select(session: session)
            host.attach(original.webView)
            host.layoutIfNeeded()
            XCTAssertTrue(pages.activePage === original)
            XCTAssertTrue(original.webView.canGoBack)
            let currentScroll = try await original.webView.evaluateJavaScript("window.scrollY")
            let draft = try await original.webView.evaluateJavaScript("document.getElementById('note').value")
            XCTAssertEqual(currentScroll as? Double, scroll)
            XCTAssertEqual(draft as? String, "draft")
        }
        pages.reconcile(validTabIDs: [])
    }

    func testAPurgedTabComesBackWithAPlainLoadAfterTheSpaceUnlocks() async throws {
        let archive = try makeTabStateArchive()
        let firstURL = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        var secret = BrowserTab(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeStateSpace(
            tabs: [secret],
            accessPolicy: .deviceOwnerAuthentication
        )
        var session = presented([protectedSpace], showing: protectedSpace.id)
        let browser = BrowserStore.hostingPages(session.session)
        browser.unlockForTesting(protectedSpace)
        let pages = MobileBrowserPageStore(
            browser: browser,
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
        session = presented([
                makeStateSpace(
                    id: protectedSpace.id,
                    profile: protectedSpace.profile,
                    tabs: [secret],
                    accessPolicy: .deviceOwnerAuthentication
                )
            ], showing: protectedSpace.id, tabs: [protectedSpace.id: secret.id])
        pages.select(session: session)
        let restoredPage = try XCTUnwrap(pages.activePage)

        XCTAssertFalse(restoredPage === originalPage)
        XCTAssertEqual(
            restoredPage.live.pendingNavigationURL ?? restoredPage.webView.url,
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
        let openSpace = makeStateSpace(tabs: [tab])
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(BrowserSession(spaces: [openSpace])),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(
            session: presented([openSpace], showing: openSpace.id)
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
            accessPolicy: .deviceOwnerAuthentication
        )
        var session = presented([protectedSpace], showing: protectedSpace.id)
        let browser = BrowserStore.hostingPages(session.session)
        browser.unlockForTesting(protectedSpace)
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pages.select(session: session)
        try await load(url, in: try XCTUnwrap(pages.activePage))
        // Idle unloading, not a relock: an unlocked protected Space archives like
        // any other, which is what makes the relock purge worth having.
        session = presented([
                makeStateSpace(
                    id: protectedSpace.id,
                    profile: protectedSpace.profile,
                    tabs: [first, second],
                    accessPolicy: .deviceOwnerAuthentication
                )
            ], showing: protectedSpace.id, tabs: [protectedSpace.id: second.id])
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

    /// A window's view of `spaces`: what it shows is window state, so fixtures
    /// pass it beside the session. Spaces without a chosen tab show their
    /// fallback.
    private func presented(
        _ spaces: [BrowserSpace], showing spaceID: SpaceID, tabs: [SpaceID: TabID] = [:]
    ) -> BrowserPresentedSession {
        BrowserPresentedSession(
            session: BrowserSession(spaces: spaces),
            window: .preview(showing: spaceID, tabs: shownTabs(in: spaces, tabs: tabs)))
    }

    /// The tab each of `spaces` shows: the one `tabs` names, else the Space's
    /// fallback by the core's rule.
    private func shownTabs(in spaces: [BrowserSpace], tabs: [SpaceID: TabID] = [:]) -> [SpaceID: TabID] {
        let core = CrestCore()
        var chosen = tabs
        for space in spaces where chosen[space.id] == nil {
            chosen[space.id] = core.fallbackTabID(in: space)
        }
        return chosen
    }

    /// The tab `session` shows in each of its Spaces that shows one.
    private func shownTabs(of session: BrowserPresentedSession) -> [SpaceID: TabID] {
        var shown: [SpaceID: TabID] = [:]
        for space in session.spaces {
            shown[space.id] = session.selectedTabID(in: space.id)
        }
        return shown
    }

    private func makeStateSpace(
        id: SpaceID = SpaceID(),
        profile: BrowsingProfile = BrowsingProfile(),
        tabs: [BrowserTab],
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
            accessPolicy: accessPolicy
        )
    }

    private func makePopupContext(
        browsingMode: BrowserBrowsingMode = .standard,
        tabStateArchive: (any BrowserTabStateArchiving)? = nil
    ) throws -> MobilePopupAdoptionContext {
        let space = makePopupSpace()
        let store = BrowserStore.hostingPages(
            BrowserSession(spaces: [space]),
            showing: space.id,
            tabs: shownTabs(in: [space])
        )
        let pages = MobileBrowserPageStore(
            browser: store,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: tabStateArchive == nil,
            tabStateArchive: tabStateArchive,
            popupTabHost: store.popupTabHost
        )
        pages.select(session: store.presented)
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
            tabs: [openerTab]
        )
    }
}

/// Stands in for WebKit's persistent-store removal so a Space can be deleted in a
/// test without touching the simulator's real WebKit data.
@MainActor
private final class MobileRecordingWebsiteDataStoreRemover:
    BrowserEngineProfileRemoving
{
    private(set) var removedProfileIDs: [UUID] = []

    func removeProfile(_ profile: BrowsingProfile, ephemeral: Bool) async throws {
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
    private let stubModifierFlags: UIKeyModifierFlags
    private let stubButtonNumber: UIEvent.ButtonMask

    init(
        url: URL?, navigationType: WKNavigationType, modifierFlags: UIKeyModifierFlags = [],
        buttonNumber: UIEvent.ButtonMask = []
    ) {
        // `window.open()` without a destination reaches WebKit as a request
        // without a URL, which a stub can only reproduce by clearing it.
        var request = URLRequest(url: URL(fileURLWithPath: "/"))
        request.url = url
        stubRequest = request
        stubNavigationType = navigationType
        stubModifierFlags = modifierFlags
        stubButtonNumber = buttonNumber
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { stubNavigationType }
    override var targetFrame: WKFrameInfo? { nil }
    override var modifierFlags: UIKeyModifierFlags { stubModifierFlags }
    override var buttonNumber: UIEvent.ButtonMask { stubButtonNumber }
    var browserSourceOrigin: SiteOrigin? { nil }
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
        mimeType: String = "application/octet-stream",
        basicAuthentication: (username: String, password: String)? = nil
    ) throws {
        listener = try NWListener(using: .tcp, on: .any)
        let header = """
            HTTP/1.1 200 OK\r
            Content-Type: \(mimeType)\r
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

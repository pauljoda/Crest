import Foundation
import WebKit
import XCTest

@testable import Crest

final class BrowserNavigationPolicyTests: XCTestCase {
    func testModifiedLinkFocusChoiceAndShiftInversion() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/research"))
        for focusesNewTabs in [false, true] {
            for shift in [false, true] {
                XCTAssertEqual(
                    BrowserModifiedLinkDisposition.classify(
                        destinationURL: url,
                        isUserActivatedLink: true,
                        isCommandModified: true,
                        isShiftModified: shift,
                        isMiddleClick: false,
                        focusesNewTabs: focusesNewTabs
                    ),
                    focusesNewTabs != shift ? .foregroundTab(url) : .backgroundTab(url)
                )
            }
        }
    }

    func testInlineDirectVideoUsesBrowserOwnedPlaybackDocument() throws {
        let url = try XCTUnwrap(
            URL(string: "https://media.example/watch?id=direct&quality=source")
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
        XCTAssertEqual(navigation.mimeType, "video/mp4")
        XCTAssertTrue(navigation.responseHTML.contains("<video"))
        XCTAssertTrue(navigation.responseHTML.contains("controls"))
        XCTAssertTrue(navigation.responseHTML.contains("playsinline"))
        XCTAssertTrue(navigation.responseHTML.contains("role=\"alert\""))
        XCTAssertTrue(
            navigation.responseHTML.contains(
                "https://media.example/watch?id=direct&amp;quality=source"
            )
        )
    }

    func testDirectMediaUsesTheFinalResponseURLAfterRedirects() throws {
        let finalURL = try XCTUnwrap(
            URL(string: "https://cdn.example/assets/redirected.mp4?token=one&part=two")
        )
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: finalURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "video/mp4"]
            )
        )

        let navigation = try XCTUnwrap(
            BrowserDirectMediaNavigation.classify(
                canShowMIMEType: true,
                isForMainFrame: true,
                response: response
            )
        )

        XCTAssertEqual(navigation.request.url, finalURL)
        XCTAssertTrue(
            navigation.responseHTML.contains(
                "https://cdn.example/assets/redirected.mp4?token=one&amp;part=two"
            )
        )
    }

    func testOnlyDisplayableInlineTopLevelMediaUsesPlaybackDocument() throws {
        let videoURL = try XCTUnwrap(URL(string: "https://media.example/movie.mp4"))
        let pageURL = try XCTUnwrap(URL(string: "https://media.example/page"))
        let attachment = try XCTUnwrap(
            HTTPURLResponse(
                url: videoURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "video/mp4",
                    "Content-Disposition": "attachment; filename=movie.mp4",
                ]
            )
        )
        let mismatched = try XCTUnwrap(
            HTTPURLResponse(
                url: videoURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/octet-stream"]
            )
        )
        let ordinaryPage = try XCTUnwrap(
            HTTPURLResponse(
                url: pageURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html"]
            )
        )

        XCTAssertNil(
            BrowserDirectMediaNavigation.classify(
                canShowMIMEType: false,
                isForMainFrame: true,
                response: attachment
            )
        )
        XCTAssertNil(
            BrowserDirectMediaNavigation.classify(
                canShowMIMEType: true,
                isForMainFrame: true,
                response: attachment
            )
        )
        XCTAssertNil(
            BrowserDirectMediaNavigation.classify(
                canShowMIMEType: true,
                isForMainFrame: true,
                response: mismatched
            )
        )
        XCTAssertNil(
            BrowserDirectMediaNavigation.classify(
                canShowMIMEType: true,
                isForMainFrame: true,
                response: ordinaryPage
            )
        )
        XCTAssertNil(
            BrowserDirectMediaNavigation.classify(
                canShowMIMEType: true,
                isForMainFrame: false,
                response: try XCTUnwrap(
                    HTTPURLResponse(
                        url: videoURL,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "video/mp4"]
                    )
                )
            )
        )
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

    func testAttachmentDispositionDownloadsEvenDisplayableContent() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/report"))
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/plain",
                    "Content-Disposition": "attachment; filename=report.txt",
                ]
            )
        )

        XCTAssertEqual(
            BrowserNavigationDecider.decidePolicy(
                canShowMIMEType: true,
                response: response
            ),
            .download
        )
    }

    func testDownloadTakesPrecedenceOverTargetlessNavigation() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/archive.zip"))

        let intent = BrowserNavigationIntent.classify(
            url: url,
            hasTargetFrame: false,
            shouldPerformDownload: true
        )

        XCTAssertEqual(intent, .download)
    }

    func testCommandAndMiddleClickedWebLinksUseNativeTabDisposition() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))

        XCTAssertTrue(BrowserMouseButtonPolicy.isMiddleButton(number: 1 << 2))
        XCTAssertFalse(BrowserMouseButtonPolicy.isMiddleButton(number: 0))
        XCTAssertFalse(BrowserMouseButtonPolicy.isMiddleButton(number: 1))
        XCTAssertFalse(BrowserMouseButtonPolicy.isMiddleButton(number: 2))

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
        XCTAssertEqual(
            BrowserModifiedLinkDisposition.classify(
                destinationURL: url,
                isUserActivatedLink: true,
                isCommandModified: false,
                isShiftModified: false,
                isMiddleClick: true
            ),
            .backgroundTab(url)
        )
    }

    func testModifiedLinkDispositionRejectsOrdinaryNonLinkAndNonWebNavigation() throws {
        let webURL = try XCTUnwrap(URL(string: "https://example.com/reference"))
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))

        XCTAssertEqual(
            BrowserModifiedLinkDisposition.classify(
                destinationURL: webURL,
                isUserActivatedLink: true,
                isCommandModified: false,
                isShiftModified: false,
                isMiddleClick: false
            ),
            .navigate
        )
        XCTAssertEqual(
            BrowserModifiedLinkDisposition.classify(
                destinationURL: webURL,
                isUserActivatedLink: false,
                isCommandModified: true,
                isShiftModified: false,
                isMiddleClick: false
            ),
            .navigate
        )
        XCTAssertEqual(
            BrowserModifiedLinkDisposition.classify(
                destinationURL: mailURL,
                isUserActivatedLink: true,
                isCommandModified: true,
                isShiftModified: false,
                isMiddleClick: false
            ),
            .navigate
        )
    }

    func testExplicitLinksAndFormsDoNotBecomeScriptedPopups() {
        XCTAssertEqual(
            BrowserPopupTrigger.classify(.linkActivated),
            .explicitUserNavigation
        )
        XCTAssertEqual(
            BrowserPopupTrigger.classify(.formSubmitted),
            .explicitUserNavigation
        )
    }

    func testNonLinkWindowRequestsRemainScriptedForExternalSchemeConsent() {
        XCTAssertEqual(BrowserPopupTrigger.classify(.other), .scripted)
        XCTAssertEqual(BrowserPopupTrigger.classify(.reload), .scripted)
    }

    func testExternalSchemeNavigationIntentOutranksDownloadsAndNewTabs() throws {
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))

        XCTAssertEqual(
            BrowserNavigationIntent.classify(
                url: mailURL,
                hasTargetFrame: false,
                shouldPerformDownload: true
            ),
            .handOffToSystem(mailURL)
        )
        XCTAssertEqual(
            BrowserNavigationIntent.classify(
                url: try XCTUnwrap(URL(string: "javascript:alert(1)")),
                hasTargetFrame: true,
                shouldPerformDownload: false
            ),
            .blockScheme
        )
        XCTAssertEqual(
            BrowserNavigationIntent.classify(
                url: try XCTUnwrap(URL(string: "https://example.com/next")),
                hasTargetFrame: true,
                shouldPerformDownload: false
            ),
            .allow
        )
    }
}

@MainActor
final class BrowserExternalSchemeCoordinatorTests: XCTestCase {
    func testUserInitiatedHandOffPromptsOnceThenRemembersTheApproval() async throws {
        let harness = Harness(response: .openAndRemember)
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))

        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .explicitUserNavigation,
            origin: harness.origin
        )

        XCTAssertEqual(harness.opened, [mailURL])
        XCTAssertEqual(harness.promptCount, 1)
        XCTAssertEqual(
            harness.permissionCenter.decision(
                for: .externalApplications,
                origin: harness.origin,
                detail: "mailto",
                in: harness.spaceID
            ),
            .grantPersistently
        )

        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .explicitUserNavigation,
            origin: harness.origin
        )

        XCTAssertEqual(harness.opened, [mailURL, mailURL])
        XCTAssertEqual(harness.promptCount, 1, "A remembered approval must skip the prompt.")
    }

    func testOpeningOnceDoesNotRememberTheApproval() async throws {
        let harness = Harness(response: .open)
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))

        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .explicitUserNavigation,
            origin: harness.origin
        )
        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .explicitUserNavigation,
            origin: harness.origin
        )

        XCTAssertEqual(harness.opened.count, 2)
        XCTAssertEqual(harness.promptCount, 2)
        XCTAssertTrue(harness.permissionCenter.records(in: harness.spaceID).isEmpty)
    }

    func testCancellingTheHandOffNeitherOpensNorRemembersABlock() async throws {
        let harness = Harness(response: .cancel)
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))

        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .explicitUserNavigation,
            origin: harness.origin
        )

        XCTAssertTrue(harness.opened.isEmpty)
        XCTAssertEqual(harness.promptCount, 1)
        XCTAssertTrue(harness.permissionCenter.records(in: harness.spaceID).isEmpty)
    }

    func testScriptedHandOffPromptsAndOpensOnlyAfterApproval() async throws {
        let harness = Harness(response: .openAndRemember)
        let meetingURL = try XCTUnwrap(URL(string: "zoommtg://zoom.us/join?confno=1"))

        await harness.coordinator.resolve(
            destinationURL: meetingURL,
            trigger: .scripted,
            origin: harness.origin
        )

        XCTAssertEqual(harness.opened, [meetingURL])
        XCTAssertEqual(harness.promptCount, 1)
    }

    func testScriptedHandOffOpensWhenTheOriginAlreadyApprovedThatScheme() async throws {
        let harness = Harness(response: .cancel)
        let meetingURL = try XCTUnwrap(URL(string: "zoommtg://zoom.us/join?confno=1"))
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))
        harness.permissionCenter.setDecision(
            .grantPersistently,
            for: .externalApplications,
            origin: harness.origin,
            detail: "zoommtg",
            in: harness.spaceID
        )

        await harness.coordinator.resolve(
            destinationURL: meetingURL,
            trigger: .scripted,
            origin: harness.origin
        )
        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .scripted,
            origin: harness.origin
        )

        XCTAssertEqual(
            harness.opened,
            [meetingURL],
            "Approving one scheme must not approve every other scheme."
        )
        XCTAssertEqual(
            harness.promptCount,
            1,
            "An unapproved scheme from the same origin must still ask."
        )
    }

    func testARememberedBlockSkipsThePromptAndTheHandOff() async throws {
        let harness = Harness(response: .openAndRemember)
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))
        harness.permissionCenter.setDecision(
            .denyPersistently,
            for: .externalApplications,
            origin: harness.origin,
            detail: "mailto",
            in: harness.spaceID
        )

        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .explicitUserNavigation,
            origin: harness.origin
        )

        XCTAssertTrue(harness.opened.isEmpty)
        XCTAssertEqual(harness.promptCount, 0)
    }

    func testAnOriginlessHandOffIsRefusedBecauseNoChoiceCouldBeRemembered() async throws {
        let harness = Harness(response: .openAndRemember)
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))

        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .explicitUserNavigation,
            origin: nil
        )

        XCTAssertTrue(harness.opened.isEmpty)
        XCTAssertEqual(harness.promptCount, 0)
    }

    @MainActor
    private final class Harness {
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "mail.example", port: 443)
        let permissionCenter = BrowserSitePermissionCenter()
        let coordinator: BrowserExternalSchemeCoordinator
        private(set) var opened: [URL] = []
        private(set) var promptCount = 0

        init(response: BrowserExternalSchemePromptResponse) {
            var recordOpen: (URL) -> Void = { _ in }
            var recordPrompt: () -> Void = {}
            coordinator = BrowserExternalSchemeCoordinator(
                spaceID: spaceID,
                spaceName: "Work",
                permissionCenter: permissionCenter,
                prompt: { _, _, _ in
                    recordPrompt()
                    return response
                },
                opensExternalURL: { recordOpen($0) }
            )
            recordOpen = { [weak self] url in self?.opened.append(url) }
            recordPrompt = { [weak self] in self?.promptCount += 1 }
        }
    }
}

@MainActor
final class BrowserDownloadNavigationLifecycleTests: XCTestCase {
    func testKnownDownloadBypassesPeekBeforeNavigationStarts() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://saved.example/home"))
        let downloadURL = try XCTUnwrap(URL(string: "https://files.example/report.pdf"))
        let tab = BrowserTab(
            title: "Saved",
            url: sourceURL,
            savedURL: sourceURL,
            placement: .pinned
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Test",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
        var peekRequest: BrowserPeekRequest?
        let pool = BrowserPagePool(openPeek: { peekRequest = $0 })
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)
        let recorder = DownloadPolicyRecorder()

        page.webView(
            page.webView,
            decidePolicyFor: StubKnownDownloadNavigationAction(url: downloadURL)
        ) { recorder.policy = $0 }

        XCTAssertEqual(recorder.policy, .download)
        XCTAssertNil(
            peekRequest,
            "A download WebKit identifies before loading must never create a Peek."
        )
    }
}

@MainActor
final class BrowserWebKitStagedNavigationTests: XCTestCase {
    /// A staged Peek request is spent by the first page that asks for it, never
    /// reaches a page in another website data store, and never replays a body.
    func testStagedLinkIsOneShotAndStaysInItsDataStore() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/next"))
        var request = URLRequest(url: url)
        request.setValue("https://example.com/source", forHTTPHeaderField: "Referer")
        let store = WKWebsiteDataStore.nonPersistent()
        func page(_ store: WKWebsiteDataStore) -> BrowserWebKitPageEngine {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = store
            return BrowserWebKitPageEngine(webView: WKWebView(frame: .zero, configuration: configuration))
        }
        let source = page(store)

        let crossStore = try XCTUnwrap(BrowserWebKitPageEngine.stageLink(request, from: source.webView))
        XCTAssertFalse(page(.nonPersistent()).stageNavigation(crossStore, expecting: url))
        XCTAssertFalse(page(store).stageNavigation(crossStore, expecting: url), "A refused token is spent.")

        let navigation = try XCTUnwrap(BrowserWebKitPageEngine.stageLink(request, from: source.webView))
        XCTAssertTrue(page(store).stageNavigation(navigation, expecting: url))
        XCTAssertFalse(page(store).stageNavigation(navigation, expecting: url))

        var post = request
        post.httpMethod = "POST"
        XCTAssertNil(BrowserWebKitPageEngine.stageLink(post, from: source.webView))
    }
}

@MainActor
final class BrowserPopupSchemeRoutingTests: XCTestCase {

    func testAPopupMayNotReachAScriptOrFileURLThroughAnyRoute() throws {
        for address in ["javascript:alert(1)", "file:///etc/passwd"] {
            XCTAssertEqual(
                BrowserPopupSchemeRouting.classify(
                    destinationURL: try XCTUnwrap(URL(string: address))
                ),
                .blocked,
                "\(address) may neither load nor be handed to another app."
            )
        }
    }

    func testAMailtoPopupHandsOffAndNeverAdoptsOrOpensATab() throws {
        let harness = Harness()
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))

        let webView = harness.resolveOpen(
            url: mailURL,
            navigationType: .linkActivated,
            currentURL: try XCTUnwrap(URL(string: "https://mail.example/inbox"))
        )

        XCTAssertNil(webView)
        XCTAssertEqual(harness.handedOff.map(\.url), [mailURL])
        XCTAssertEqual(harness.handedOff.first?.trigger, .explicitUserNavigation)
        XCTAssertEqual(
            harness.handedOff.first?.origin,
            BrowserSiteOrigin(scheme: "https", host: "mail.example", port: 443)
        )
        XCTAssertEqual(
            harness.adoptedURLs.count,
            0,
            "A mailto: popup must never reach tab adoption."
        )
        XCTAssertTrue(
            harness.openedTabURLs.isEmpty,
            "The hand-off replaces the tab; it must not also open one."
        )
    }

    func testAScriptedExternalSchemePopupStillReachesTheConsentPathAsScripted() throws {
        let harness = Harness()
        let meetingURL = try XCTUnwrap(URL(string: "zoommtg://zoom.us/join?confno=1"))

        _ = harness.resolveOpen(
            url: meetingURL,
            navigationType: .other,
            currentURL: try XCTUnwrap(URL(string: "https://meet.example/room"))
        )

        XCTAssertEqual(harness.handedOff.first?.trigger, .scripted)
        XCTAssertTrue(harness.openedTabURLs.isEmpty)
        XCTAssertEqual(harness.adoptedURLs.count, 0)
    }

    func testABlockedSchemePopupIsDroppedWithoutAHandOffOrATab() throws {
        for address in ["javascript:alert(1)", "file:///etc/passwd"] {
            let harness = Harness()

            let webView = harness.resolveOpen(
                url: try XCTUnwrap(URL(string: address)),
                navigationType: .linkActivated,
                currentURL: try XCTUnwrap(URL(string: "https://hostile.example/"))
            )

            XCTAssertNil(webView)
            XCTAssertTrue(harness.handedOff.isEmpty, "\(address) must not launch another app.")
            XCTAssertTrue(harness.openedTabURLs.isEmpty)
            XCTAssertEqual(harness.adoptedURLs.count, 0)
        }
    }

    func testAUserActivatedWindowOpenClassifiedAsOtherStillReachesAdoption() throws {
        let harness = Harness()
        let signInURL = try XCTUnwrap(URL(string: "https://accounts.google.com/gsi/transform"))

        _ = harness.resolveOpen(
            url: signInURL,
            navigationType: .other,
            currentURL: try XCTUnwrap(URL(string: "https://www.reddit.com/"))
        )

        XCTAssertEqual(harness.adoptedURLs, [signInURL])
        XCTAssertEqual(
            harness.openedTabURLs,
            [signInURL],
            "The harness cannot host an adopted web view, so the tested request falls back to a plain tab only after reaching adoption."
        )
    }

    @MainActor
    private final class Harness {
        struct HandOff: Equatable {
            let url: URL
            let trigger: BrowserPopupTrigger
            let origin: BrowserSiteOrigin?
        }

        let coordinator: BrowserPopupCoordinator
        private(set) var handedOff: [HandOff] = []
        private(set) var openedTabURLs: [URL] = []
        private(set) var adoptedURLs: [URL?] = []

        init() {
            var recordOpenTab: (URL) -> Void = { _ in }
            var recordHandOff: (HandOff) -> Void = { _ in }
            coordinator = BrowserPopupCoordinator(
                openNewTab: { recordOpenTab($0) },
                handOffExternalScheme: { url, trigger, origin in
                    recordHandOff(HandOff(url: url, trigger: trigger, origin: origin))
                }
            )
            recordOpenTab = { [weak self] url in self?.openedTabURLs.append(url) }
            recordHandOff = { [weak self] handOff in self?.handedOff.append(handOff) }
        }

        func resolveOpen(
            url: URL?,
            navigationType: WKNavigationType,
            currentURL: URL?
        ) -> WKWebView? {
            coordinator.resolveOpen(
                for: StubNewWindowNavigationAction(
                    url: url,
                    navigationType: navigationType
                ),
                currentURL: currentURL
            ) { requestedURL in
                self.adoptedURLs.append(requestedURL)
                return nil
            }
        }
    }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so this stands in
/// for the one handed to `createWebViewWith`: no target frame, and a navigation
/// type that selects the popup trigger under test. It deliberately has no source
/// frame, which is how the coordinator's fallback to the visible page is covered.
private final class StubNewWindowNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest
    private let stubNavigationType: WKNavigationType

    init(url: URL?, navigationType: WKNavigationType) {
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

private final class StubKnownDownloadNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest

    init(url: URL) {
        stubRequest = URLRequest(url: url)
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { .linkActivated }
    override var targetFrame: WKFrameInfo? { nil }
    override var shouldPerformDownload: Bool { true }
    var browserSourceOrigin: BrowserSiteOrigin? { nil }
}

@MainActor
private final class DownloadPolicyRecorder {
    var policy: WKNavigationActionPolicy?
}

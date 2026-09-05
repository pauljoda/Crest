import AppKit
import WebKit
import XCTest

@testable import Crest

/// Opt in on an interactive Mac with CREST_PIP_LIVE_TESTS=1. These tests show
/// real system PiP windows; the ordinary suite tests classification and races.
@MainActor
final class BrowserPictureInPictureLiveTests: XCTestCase {
    func testDisablingAutomaticPiPPreservesManualEntry() async throws {
        try requireLiveSession()
        let setup = makeSetup()
        defer {
            setup.pool.reconcile(validTabIDs: [])
            setup.window.orderOut(nil)
        }
        let original = UserDefaults.standard.object(forKey: BrowserAutomaticPictureInPicturePreference.key)
        UserDefaults.standard.set(false, forKey: BrowserAutomaticPictureInPicturePreference.key)
        defer { UserDefaults.standard.set(original, forKey: BrowserAutomaticPictureInPicturePreference.key) }
        let source = try await loadFixture(setup, tab: setup.tabs[0])
        try await play(source)
        try await wait("player qualifies") { source.pictureInPicture.canAutomaticallyEnterPictureInPicture }
        setup.pool.select(tab: setup.tabs[1], space: setup.space)
        setup.window.contentView = setup.pool.activePage?.webView
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(source.pictureInPicture.isPictureInPictureActive)
        setup.pool.select(tab: setup.tabs[0], space: setup.space)
        setup.window.contentView = source.webView
        try await enterUsingNativeContextMenu(source.webView)
        try await wait("manual PiP remains enabled") { source.pictureInPicture.isPictureInPictureActive }
        setup.pool.select(tab: setup.tabs[1], space: setup.space)
        setup.window.contentView = setup.pool.activePage?.webView
        setup.pool.select(tab: setup.tabs[0], space: setup.space)
        setup.window.contentView = source.webView
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(
            source.pictureInPicture.isPictureInPictureActive, "Returning to a tab does not close manually entered PiP.")
        setup.pool.deactivatePagePresentation()
        try await wait("hiding protected presentation closes PiP") {
            !BrowserDesktopPictureInPictureAccess.isSystemOccupied()
        }
    }

    func testTabSwitchStartsNativePiPSkipsCompetingVideoAndReturnsInline() async throws {
        try requireLiveSession()
        let setup = makeSetup()
        defer {
            setup.pool.reconcile(validTabIDs: [])
            setup.window.orderOut(nil)
        }
        let originalPreference = UserDefaults.standard.object(forKey: BrowserAutomaticPictureInPicturePreference.key)
        UserDefaults.standard.set(true, forKey: BrowserAutomaticPictureInPicturePreference.key)
        defer { UserDefaults.standard.set(originalPreference, forKey: BrowserAutomaticPictureInPicturePreference.key) }

        let source = try await loadFixture(setup, tab: setup.tabs[0])
        try await play(source)
        try await wait("source player qualifies") { source.pictureInPicture.canAutomaticallyEnterPictureInPicture }
        // Return before WebKit has acknowledged entry. A late native result
        // must return inline, and its old reservation must not block the next departure.
        setup.pool.select(tab: setup.tabs[1], space: setup.space)
        setup.window.contentView = setup.pool.activePage?.webView
        setup.pool.select(tab: setup.tabs[0], space: setup.space)
        setup.window.contentView = source.webView
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(source.pictureInPicture.isPictureInPictureActive)
        XCTAssertFalse(BrowserDesktopPictureInPictureAccess.isSystemOccupied())
        try await wait("returned source qualifies again") {
            source.pictureInPicture.canAutomaticallyEnterPictureInPicture
        }
        setup.pool.select(tab: setup.tabs[1], space: setup.space)
        let second = try XCTUnwrap(setup.pool.activePage)
        setup.window.contentView = second.webView
        try await wait("native PiP enters") { source.pictureInPicture.isPictureInPictureActive }
        try await wait("system PiP window appears") { BrowserDesktopPictureInPictureAccess.isSystemOccupied() }
        XCTAssertNil(source.webView.window, "The video continues after its source view detaches.")
        let framesBefore =
            try await source.webView.evaluateJavaScript(
                "document.querySelector('video').getVideoPlaybackQuality().totalVideoFrames") as? Int
        try await Task.sleep(for: .milliseconds(700))
        let framesAfter =
            try await source.webView.evaluateJavaScript(
                "document.querySelector('video').getVideoPlaybackQuality().totalVideoFrames") as? Int
        XCTAssertGreaterThan(try XCTUnwrap(framesAfter), try XCTUnwrap(framesBefore))

        try loadFixtureContent(in: second)
        try await play(second)
        try await wait("competing player qualifies") { second.pictureInPicture.canAutomaticallyEnterPictureInPicture }
        setup.pool.select(tab: setup.tabs[2], space: setup.space)
        setup.window.contentView = setup.pool.activePage?.webView
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(source.pictureInPicture.isPictureInPictureActive)
        XCTAssertFalse(second.pictureInPicture.isPictureInPictureActive)
        _ = try await source.webView.evaluateJavaScript("document.querySelector('video').pause(); null")
        let residency = await source.residencyDecision(isSelected: false)
        XCTAssertFalse(residency.allowsAutomaticUnload, "Paused PiP still owns its source page.")

        setup.pool.select(tab: setup.tabs[0], space: setup.space)
        setup.window.contentView = source.webView
        try await wait("return restores inline video") { !source.pictureInPicture.isPictureInPictureActive }
        let mode =
            try await source.webView.evaluateJavaScript("document.querySelector('video').webkitPresentationMode")
            as? String
        XCTAssertEqual(mode, "inline")
    }

    func testYouTubePlayerAutomaticallyEntersNativePiP() async throws {
        try requireLiveSession()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CREST_PIP_WEBSITE_TESTS"] == "1",
            "Enable CREST_PIP_WEBSITE_TESTS=1 for live websites.")
        let setup = makeSetup()
        defer {
            setup.pool.reconcile(validTabIDs: [])
            setup.window.orderOut(nil)
        }
        let original = UserDefaults.standard.object(forKey: BrowserAutomaticPictureInPicturePreference.key)
        UserDefaults.standard.set(true, forKey: BrowserAutomaticPictureInPicturePreference.key)
        defer { UserDefaults.standard.set(original, forKey: BrowserAutomaticPictureInPicturePreference.key) }
        setup.pool.select(tab: setup.tabs[0], space: setup.space)
        let source = try XCTUnwrap(setup.pool.activePage)
        setup.window.contentView = source.webView
        source.load(try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")))
        try await play(source, seconds: 45)
        try await wait("YouTube player qualifies", seconds: 15) {
            source.pictureInPicture.canAutomaticallyEnterPictureInPicture
        }
        setup.pool.select(tab: setup.tabs[1], space: setup.space)
        setup.window.contentView = setup.pool.activePage?.webView
        try await wait("YouTube enters system PiP", seconds: 10) { source.pictureInPicture.isPictureInPictureActive }
        try await wait("YouTube PiP window appears") { BrowserDesktopPictureInPictureAccess.isSystemOccupied() }
        _ = try await source.webView.evaluateJavaScript("document.querySelector('video').pause(); null")
        setup.pool.unloadPage(for: setup.tabs[0].id)
        try await wait("closing source closes PiP") { !BrowserDesktopPictureInPictureAccess.isSystemOccupied() }
    }

    func testLockingBackgroundSpaceClosesItsPictureInPicture() async throws {
        try requireLiveSession()
        let setup = makeSetup()
        defer {
            setup.pool.reconcile(validTabIDs: [])
            setup.window.orderOut(nil)
        }
        var protectedSpace = setup.space
        protectedSpace.accessPolicy = .deviceOwnerAuthentication
        setup.pool.select(tab: setup.tabs[0], space: protectedSpace)
        let source = try XCTUnwrap(setup.pool.activePage)
        setup.window.contentView = source.webView
        try loadFixtureContent(in: source)
        try await play(source)
        try await wait("protected player qualifies") { source.pictureInPicture.canAutomaticallyEnterPictureInPicture }
        _ = try await source.webView.evaluateJavaScript(
            "document.querySelector('video').requestPictureInPicture(); null")
        try await wait("system PiP window appears") { BrowserDesktopPictureInPictureAccess.isSystemOccupied() }
        let other = BrowserTab.startPage()
        let otherSpace = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Other", symbol: "globe",
            accent: .indigo, folders: [], tabs: [other], selectedTabID: other.id)
        setup.pool.select(tab: other, space: otherSpace)
        setup.window.contentView = setup.pool.activePage?.webView
        setup.pool.relockProtectedSpace(protectedSpace)
        try await wait("locking background Space closes its PiP") {
            !BrowserDesktopPictureInPictureAccess.isSystemOccupied()
        }
        XCTAssertEqual(setup.pool.activeTabID, other.id)
    }

    private func enterUsingNativeContextMenu(_ webView: WKWebView) async throws {
        let capture = MenuCapture()
        NotificationCenter.default.addObserver(
            capture, selector: #selector(MenuCapture.menuWillTrack(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(capture) }
        let pointValue = try await webView.evaluateJavaScript(
            "(() => { const r = document.querySelector('video').getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2}; })()"
        )
        let point = try XCTUnwrap(pointValue as? [String: Double])
        let local = NSPoint(x: try XCTUnwrap(point["x"]), y: try XCTUnwrap(point["y"]))
        let location = webView.convert(local, to: nil)
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown, location: location,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: try XCTUnwrap(webView.window).windowNumber, context: nil, eventNumber: 1,
                clickCount: 1, pressure: 1))
        webView.rightMouseDown(with: event)
        try await wait("native PiP context item exists: \(capture.items)") { capture.found }
        XCTAssertTrue(capture.enabled, "WebKit's own PiP menu item must be enabled.")
    }

    @MainActor
    private final class MenuCapture: NSObject {
        var found = false
        var enabled = false
        var items: [String] = []

        @objc func menuWillTrack(_ notification: Notification) {
            guard let menu = notification.object as? NSMenu else { return }
            items = menu.items.map { "\($0.identifier?.rawValue ?? $0.title):\($0.isEnabled)" }
            print("PiP native context menu: \(items)")
            let timer = Timer(
                timeInterval: 0.05, target: self, selector: #selector(selectPictureInPicture(_:)),
                userInfo: menu, repeats: false)
            RunLoop.main.add(timer, forMode: .eventTracking)
        }

        @objc private func selectPictureInPicture(_ timer: Timer) {
            guard let menu = timer.userInfo as? NSMenu else { return }
            guard
                let index = menu.items.firstIndex(where: {
                    $0.identifier?.rawValue.contains("PictureInPicture") == true
                })
            else {
                menu.cancelTracking()
                return
            }
            found = true
            enabled = menu.items[index].isEnabled
            menu.cancelTracking()
            if enabled { menu.performActionForItem(at: index) }
        }
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "CrestTestFixtures/physical-media.html")
    }

    private func requireLiveSession() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CREST_PIP_LIVE_TESTS"] == "1",
            "Enable CREST_PIP_LIVE_TESTS=1 on an interactive Mac.")
        try XCTSkipIf(BrowserDesktopPictureInPictureAccess.isSystemOccupied(), "An existing PiP session is in use.")
    }

    private func makeSetup() -> Setup {
        let tabs = (0..<3).map { _ in BrowserTab.startPage() }
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "PiP Test", symbol: "play",
            accent: .indigo, folders: [], tabs: tabs, selectedTabID: tabs[0].id)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.title = "Crest PiP validation"
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return Setup(
            pool: BrowserPagePool(usesEphemeralWebsiteDataStores: true), space: space, tabs: tabs, window: window)
    }

    private func loadFixture(_ setup: Setup, tab: BrowserTab) async throws -> BrowserPage {
        setup.pool.select(tab: tab, space: setup.space)
        let page = try XCTUnwrap(setup.pool.activePage)
        setup.window.contentView = page.webView
        try loadFixtureContent(in: page)
        return page
    }

    private func loadFixtureContent(in page: BrowserPage) throws {
        let media = try Data(contentsOf: fixtureURL.deletingLastPathComponent().appending(path: "sample.mp4"))
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
            .replacingOccurrences(of: "sample.mp4", with: "data:video/mp4;base64,\(media.base64EncodedString())")
        page.webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://pip.crest.test"))), responseHTML: html)
    }

    private func play(_ page: BrowserPage, seconds: TimeInterval = 10) async throws {
        do {
            try await wait("video metadata loads", seconds: seconds) {
                (try? await page.webView.evaluateJavaScript("(document.querySelector('video')?.readyState ?? 0) >= 1"))
                    as? Bool == true
            }
        } catch {
            let diagnostics = try? await page.webView.evaluateJavaScript(
                "JSON.stringify({url:location.href,title:document.title,body:document.body?.innerText.slice(0,200),video:Array.from(document.querySelectorAll('video')).map(v=>({ready:v.readyState,network:v.networkState,error:v.error?.message,src:v.currentSrc.slice(0,60)}))})"
            )
            print("PiP fixture diagnostics: \(String(describing: diagnostics))")
            throw error
        }
        _ = try await page.webView.evaluateJavaScript(
            "document.querySelector('video').muted = true; document.querySelector('video').play(); null")
    }

    private func wait(_ description: String, seconds: TimeInterval = 8, condition: @MainActor () async -> Bool)
        async throws
    {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail(description)
        throw NSError(domain: "CrestPiPLiveTest", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private struct Setup {
        let pool: BrowserPagePool
        let space: BrowserSpace
        let tabs: [BrowserTab]
        let window: NSWindow
    }
}

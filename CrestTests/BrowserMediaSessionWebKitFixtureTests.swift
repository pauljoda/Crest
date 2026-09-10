import ImageIO
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserMediaSessionWebKitFixtureTests: XCTestCase {
    func testStandardMediaSessionFixturePublishesControlsAndCleansUpOnNavigation() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/SidebarWidgets/media-session.html")
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let origin = try XCTUnwrap(
            URL(string: "https://media-session.crest.test/?title=Fixture")
        )
        let tab = BrowserTab.startPage()
        let profile = BrowsingProfile()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Media Fixture",
            symbol: "play.fill",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let store = BrowserMediaSessionStore()
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: true,
            mediaSessionStore: store
        )
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)

        page.webView.loadSimulatedRequest(
            URLRequest(url: origin),
            responseHTML: html
        )
        try await waitUntil("the fixture metadata to load without surfacing") {
            let state =
                try? await page.webView.evaluateJavaScript(
                    "document.querySelector('#status').value"
                ) as? String
            return state == "Paused" && store.sessions.isEmpty
        }
        try await page.webView.evaluateJavaScript(
            "document.querySelector('#play').click()"
        )
        try await waitUntil("the Media Session bridge to publish") {
            store.sessions.first?.title == "Fixture"
                && store.sessions.first?.availableActions
                    == [.play, .pause, .previousTrack, .nextTrack]
        }
        let session = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(session.owner.tabID, tab.id)
        XCTAssertEqual(session.owner.spaceID, space.id)
        XCTAssertEqual(session.owner.profileID, profile.id)
        XCTAssertNotNil(session.artworkData)
        XCTAssertFalse(
            session.isMuted,
            "A loaded page with an unmuted element is not reported as muted."
        )
        let widgetID = BrowserSidebarWidgetID(
            kindID: .nowPlaying,
            instanceID: session.id.id
        )

        store.perform(.nextTrack, on: widgetID)
        try await waitUntil("the page action to update standard metadata") {
            store.sessions.first?.title == "Fixture Next"
        }

        store.perform(.toggleMute, on: widgetID)
        try await waitUntil("the bridge to mute the page's media elements") {
            store.sessions.first?.isMuted == true
        }
        store.perform(.toggleMute, on: widgetID)
        try await waitUntil("the bridge to unmute the page's media elements") {
            store.sessions.first?.isMuted == false
        }

        // An unseen late document cannot replace the committed session even
        // when it reports the exact same URL. URL checks and retired IDs alone
        // cannot reject this case.
        try await page.webView.evaluateJavaScript(
            """
            webkit.messageHandlers.crestMediaSession.postMessage({
              version:1, documentIdentifier:'unseen-old-document', sequence:1,
              location:location.href, invalidated:false, active:true,
              title:'Stale', playbackState:'playing', audible:true, muted:false, actions:['play','pause']
            });
            navigator.mediaSession.metadata = new MediaMetadata({ title:'Current after stale event' }); true;
            """
        )
        try await waitUntil("the committed document to survive an unseen stale report") {
            store.sessions.first?.title == "Current after stale event"
        }

        page.webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://empty.crest.test/"))),
            responseHTML: "<html><body>No media session</body></html>"
        )
        try await waitUntil("navigation to retire the owning document") {
            store.sessions.isEmpty
        }
        page.prepareForSpaceDeletion()
    }

    func testPageContextPreservesBoundedWideStandardArtworkBeforePublishing() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/SidebarWidgets/media-session.html")
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let origin = try XCTUnwrap(
            URL(
                string:
                    "https://media-session.crest.test/?title=Large&largeArtwork=1&artworkAspect=wide"
            )
        )
        let tab = BrowserTab.startPage()
        let profile = BrowsingProfile()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Large Artwork Fixture",
            symbol: "photo",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let store = BrowserMediaSessionStore()
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: true,
            mediaSessionStore: store
        )
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)

        page.webView.loadSimulatedRequest(
            URLRequest(url: origin),
            responseHTML: html
        )
        try await waitUntil("the large-artwork fixture to load") {
            let state =
                try? await page.webView.evaluateJavaScript(
                    "document.querySelector('#status').value"
                ) as? String
            return state == "Paused"
        }
        try await page.webView.evaluateJavaScript(
            "document.querySelector('#play').click()"
        )
        try await waitUntil(
            "large page artwork to cross the bounded bridge",
            timeout: .seconds(15)
        ) {
            store.sessions.first?.artworkData != nil
        }

        let artworkData = try XCTUnwrap(store.sessions.first?.artworkData)
        XCTAssertLessThanOrEqual(
            artworkData.count,
            BrowserMediaSessionArtworkPolicy.maximumBytes
        )
        XCTAssertGreaterThan(
            artworkData.count,
            256 * 1_024,
            "Ordinary source artwork should not be recompressed by the bridge."
        )
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(artworkData as CFData, nil)
        )
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(
            try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
            640
        )
        XCTAssertEqual(
            try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int),
            360
        )
        page.prepareForSpaceDeletion()
    }

    func testMutedAutoplayPreviewDoesNotPublishUntilItBecomesAudible() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/SidebarWidgets/media-session.html")
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let origin = try XCTUnwrap(
            URL(
                string:
                    "https://media-session.crest.test/?title=Preview&mutedPreview=1"
            )
        )
        let tab = BrowserTab.startPage()
        let profile = BrowsingProfile()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Muted Preview Fixture",
            symbol: "speaker.slash.fill",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let store = BrowserMediaSessionStore()
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: true,
            mediaSessionStore: store
        )
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)

        page.webView.loadSimulatedRequest(
            URLRequest(url: origin),
            responseHTML: html
        )
        try await waitUntil("the muted preview to start") {
            let state =
                try? await page.webView.evaluateJavaScript(
                    "document.querySelector('#status').value"
                ) as? String
            return state == "Muted preview"
        }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(
            store.sessions.isEmpty,
            "Muted hover and promoted previews must not create Now Playing cards."
        )

        try await page.webView.evaluateJavaScript(
            "document.querySelector('#media').muted = false"
        )
        try await waitUntil("audible playback to qualify the session") {
            store.sessions.first?.title == "Preview"
                && store.sessions.first?.isAudible == true
        }
        page.prepareForSpaceDeletion()
    }

    func testPlayerControlsAndMediaLifetimeDetermineEligibility() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        var events: [BrowserMediaSessionPageEvent] = []
        let proxy = BrowserMediaSessionContentBridge.install(in: configuration.userContentController) {
            if let event = BrowserMediaSessionPageEventDecoder.decode($0.body) { events.append(event) }
        }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        defer { withExtendedLifetime(proxy) {} }
        webView.loadHTMLString("<main id='player'></main>", baseURL: URL(string: "https://media.crest.test"))
        try await waitUntil("the bridge") { !events.isEmpty }

        func check(_ script: String, active: Bool, _ reason: String) async throws {
            let count = events.count
            try await webView.evaluateJavaScript(script + "; globalThis.__crestMediaSessionBridge.emit(); true")
            try await waitUntil("a fresh report for " + reason) { events.count > count }
            XCTAssertEqual(events.last?.hasActiveSession, active, reason)
        }
        try await check(
            "navigator.mediaSession.playbackState='playing'", active: false,
            "a playbackState hint alone is not a player")
        try await check(
            "navigator.mediaSession.metadata=new MediaMetadata({title:'Web Audio music'}); navigator.mediaSession.setActionHandler('play',()=>{}); navigator.mediaSession.setActionHandler('pause',()=>{})",
            active: true, "explicit Web Audio music keeps standard transport controls")
        try await check(
            "navigator.mediaSession.playbackState='paused'", active: true, "explicit Web Audio music can pause")
        try await check(
            "navigator.mediaSession.playbackState='none'", active: false, "stopping Web Audio clears its session")
        try await check(
            "navigator.mediaSession.metadata=null; navigator.mediaSession.setActionHandler('play',null); navigator.mediaSession.setActionHandler('pause',null)",
            active: false, "cleared Web Audio stays inactive")
        let mediaSetup = """
            globalThis.player = document.querySelector('#player');
            globalThis.media = document.createElement('video');
            player.append(media);
            for (const [key, value] of Object.entries({ paused:false, ended:false, readyState:4,
              videoWidth:640, videoHeight:360, currentSrc:'https://media.crest.test/one.mp4' })) {
              Object.defineProperty(media, key, { configurable:true, writable:true, value });
            }
            media.style.cssText='width:640px;height:360px';
            media.dispatchEvent(new Event('playing'));
            """
        try await check(mediaSetup, active: false, "audible uncontrolled previews stay excluded")
        try await check("media.controls=true", active: true, "native controlled playback qualifies")
        try await check(
            "media.paused=true; media.dispatchEvent(new Event('pause'))", active: true, "pause retains a current player"
        )
        try await check("media.remove()", active: false, "removal clears a paused player")
        try await check("player.append(media)", active: false, "reinsertion does not restore old qualification")
        try await check(
            "media.paused=false; media.dispatchEvent(new Event('playing'))", active: true, "new playback qualifies")
        try await check(
            "media.currentSrc='https://media.crest.test/two.mp4'; media.paused=true", active: false,
            "a replacement source must play first")
        try await check(
            "media.paused=false; media.dispatchEvent(new Event('playing'))", active: true,
            "replacement playback qualifies")
        try await check(
            "media.ended=true; media.dispatchEvent(new Event('ended'))", active: false, "ended media leaves no card")
        try await check(
            "media.ended=false; media.dispatchEvent(new Event('playing'))", active: true, "replay qualifies")
        try await check(
            "player.hidden=true; history.pushState({},'', '/away')", active: false, "hidden SPA player leaves no card")
        try await check(
            "player.hidden=false; media.controls=false; player.insertAdjacentHTML('beforeend', '<button>Play</button><button>Mute</button><input type=range>')",
            active: true, "custom controls use PiP player recognition")
        try await check("media.muted=true", active: true, "muting a controlled video retains it")
        try await check(
            "player.replaceChildren(); navigator.mediaSession.playbackState='playing'", active: false,
            "stale page playbackState cannot replace removed media")
        try await check(
            "globalThis.chime=document.createElement('audio'); player.append(chime); Object.defineProperty(chime,'paused',{value:false}); chime.dispatchEvent(new Event('playing'))",
            active: false, "incidental audio without controls stays excluded")
        try await check("chime.controls=true", active: true, "ordinary native audio controls remain eligible")
        let beforeReplacement = events.count
        try await webView.evaluateJavaScript("player.replaceChildren(document.createElement('p')); true")
        try await waitUntil("DOM replacement to publish without another media event") {
            events.count > beforeReplacement
        }
        XCTAssertEqual(events.last?.hasActiveSession, false)

    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(8),
        condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description).")
    }
}

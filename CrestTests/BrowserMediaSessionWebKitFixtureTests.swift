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

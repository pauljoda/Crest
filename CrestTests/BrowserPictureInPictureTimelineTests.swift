import Testing
import WebKit

@testable import Crest

@MainActor
@Suite("Picture in Picture seeking")
struct BrowserPictureInPictureTimelineTests {
    @Test("A delayed seek cannot move the next floating video")
    func seekStaysWithItsPresentation() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        let world = WKContentWorld.defaultClient
        _ = try await view.callAsyncJavaScript(
            """
            const players = Array.from({ length: 2 }, () => {
              const player = document.createElement('video');
              document.documentElement.append(player);
              Object.defineProperties(player, {
                currentTime: { value: 12, writable: true },
                seekable: { value: { length: 1, start: () => 0, end: () => 90 } }
              });
              return player;
            });
            globalThis.players = players;
            Object.defineProperty(document, 'pictureInPictureElement', { get: () => players[0] });
            """, arguments: [:], in: nil, contentWorld: world)
        func read(_ seek: BrowserPictureInPictureTimeline.Seek? = nil) async -> BrowserPictureInPictureTimeline? {
            await BrowserPictureInPictureTimeline.read(moving: seek) { body, arguments in
                try await view.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: world)
            }
        }

        let first = try #require(await read())
        let skip = BrowserPictureInPictureTimeline.Seek(id: first.id, seconds: 10, relative: true)
        #expect(await read(skip)?.position == 22)
        _ = try await view.callAsyncJavaScript(
            "players.reverse();", arguments: [:], in: nil, contentWorld: world)
        #expect(await read(skip) == nil)
        let second = try #require(await read())
        #expect(second.id != first.id)
        #expect(second.position == 12)
    }
}

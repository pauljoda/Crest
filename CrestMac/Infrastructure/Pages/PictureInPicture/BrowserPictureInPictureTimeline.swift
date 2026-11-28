import Foundation

/// A snapshot of the seekable part of the video in the floating player.
/// The renderer gives each presentation an identity so a late drag cannot
/// seek a replacement video, even in the same document.
struct BrowserPictureInPictureTimeline: Decodable, Equatable {
    // MARK: - Static Variables

    static let skipInterval: Double = 10

    /// Runs in the active video's isolated content world. A seek re-reads the
    /// ranges, since a live window can move while the person drags the slider.
    static let script = #"""
        let video = document.pictureInPictureElement;
        while (video && !(video instanceof HTMLVideoElement))
          video = video.shadowRoot?.pictureInPictureElement;
        video ??= globalThis.__crestPictureInPicture?.activeVideo?.();
        if (!video?.isConnected) return null;
        let session = globalThis.__crestPiPTimelineSession;
        if (session?.video !== video) {
          const id = Array.from(crypto.getRandomValues(new Uint32Array(4))).join('-');
          session = { video, id };
          globalThis.__crestPiPTimelineSession = session;
          const clear = () => {
            if (globalThis.__crestPiPTimelineSession === session)
              delete globalThis.__crestPiPTimelineSession;
            video.removeEventListener('leavepictureinpicture', clear);
            video.removeEventListener('emptied', clear);
          };
          video.addEventListener('leavepictureinpicture', clear);
          video.addEventListener('emptied', clear);
        }
        if (expectedID !== null && expectedID !== session.id) return null;
        const ranges = video.seekable;
        if (!ranges.length || !Number.isFinite(video.currentTime)) return null;
        const start = ranges.start(0), end = ranges.end(ranges.length - 1);
        if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return null;
        if (expectedID !== null) {
          const target = relative ? video.currentTime + seconds : seconds;
          if (!Number.isFinite(target)) return null;
          let nearest = start;
          for (let i = 0; i < ranges.length; ++i) {
            const point = Math.min(ranges.end(i), Math.max(ranges.start(i), target));
            if (Math.abs(point - target) < Math.abs(nearest - target)) nearest = point;
          }
          video.currentTime = nearest;
        }
        return JSON.stringify({ id: session.id, start, end, position: video.currentTime });
        """#

    // MARK: - Types

    struct Seek {
        let id: String
        let seconds: Double
        let relative: Bool
    }

    // MARK: - Variables

    let id: String
    let start: Double
    let end: Double
    let position: Double

    // MARK: - Actions - Engine scripting

    @MainActor
    static func read(
        moving seek: Seek?,
        evaluate: @MainActor (String, [String: Any]) async throws -> Any?
    ) async -> Self? {
        let arguments: [String: Any] = [
            "expectedID": seek?.id as Any? ?? NSNull(),
            "seconds": seek?.seconds ?? 0,
            "relative": seek?.relative ?? false,
        ]
        guard let json = try? await evaluate(script, arguments) as? String,
            let value = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)),
            value.start.isFinite, value.end.isFinite, value.end > value.start, value.position.isFinite
        else { return nil }
        return value
    }
}

import Foundation

/// Reads the captions a page shows over its video while that video floats in
/// Picture in Picture, for an engine whose Picture in Picture window draws
/// them. A video's frames carry no captions: sites draw them over the player,
/// as YouTube does, or as the video's showing text tracks, so the floating
/// window would otherwise show none.
@MainActor
enum BrowserPictureInPictureCaptionBridge {
    static let messageHandlerName = "crestPictureInPictureCaptions"
    /// The longest caption the bridge passes on, in characters.
    static let maximumCaptionLength = 500

    static let script = BrowserContentScript(
        source: source, handlerName: messageHandlerName, mainFrameOnly: false)

    /// The caption a bridge message carries: the text the page shows over its
    /// floating video now, or empty when it shows none.
    static func caption(in message: BrowserContentMessage) -> String? {
        guard let body = message.body as? [String: Any], let caption = body["caption"] as? String else {
            return nil
        }
        return String(caption.prefix(maximumCaptionLength))
    }

    // The bridge watches only the document whose video is in Picture in
    // Picture, and only while it is: the player's caption overlay and the
    // video's showing text tracks. It posts a caption when it changes and an
    // empty one when the video returns.
    private static let source = #"""
        (() => {
          'use strict';
          if (globalThis.__crestPictureInPictureCaptions) return;
          const handler = globalThis.webkit?.messageHandlers?.crestPictureInPictureCaptions;
          if (!handler) return;
          globalThis.__crestPictureInPictureCaptions = true;
          // Caption overlays players draw over their video, by the line.
          const overlays = [{ root: '.ytp-caption-window-container', line: '.caption-visual-line' }];
          let video = null;
          let observer = null;
          let posted = '';
          let scheduled = false;
          const clean = text => text.split('\n').map(line => line.replace(/\s+/g, ' ').trim())
            .filter(Boolean).join('\n').slice(0, \#(maximumCaptionLength));
          // An overlay belongs to the floating video only when no other video
          // in the same container sits closer to it, as another player's does.
          // A second video inside the same player, such as an ad's, is as close.
          const belongsTo = (root, container, element) => {
            for (const other of container.querySelectorAll('video')) {
              if (other === element) continue;
              let ancestor = root.parentElement;
              while (ancestor && ancestor !== container && !ancestor.contains(other)) ancestor = ancestor.parentElement;
              if (ancestor !== container) return false;
            }
            return true;
          };
          const overlayFor = element => {
            for (let container = element.parentElement, depth = 0; container && depth < 6;
                 container = container.parentElement, depth++) {
              for (const overlay of overlays) {
                const root = container.querySelector(overlay.root);
                if (!root) continue;
                return belongsTo(root, container, element) ? { container, root, line: overlay.line } : null;
              }
            }
            return null;
          };
          const cueText = cue => {
            const fragment = cue.getCueAsHTML?.();
            return fragment ? fragment.textContent : String(cue.text || '').replace(/<[^>]*>/g, '');
          };
          const caption = () => {
            if (!video) return '';
            const overlay = overlayFor(video);
            if (overlay) {
              const lines = Array.from(overlay.root.querySelectorAll(overlay.line), line => line.textContent);
              const text = clean(lines.length ? lines.join('\n') : overlay.root.textContent);
              if (text) return text;
            }
            const cues = [];
            for (const track of Array.from(video.textTracks || [])) {
              if (track.mode !== 'showing' || !track.activeCues) continue;
              for (const cue of Array.from(track.activeCues)) cues.push(cueText(cue));
            }
            return clean(cues.join('\n'));
          };
          const post = text => {
            if (text === posted) return;
            posted = text;
            try { handler.postMessage({ caption: text }); } catch (_) {}
          };
          const schedule = () => {
            if (scheduled) return;
            scheduled = true;
            setTimeout(() => { scheduled = false; post(caption()); }, 50);
          };
          const detach = () => {
            observer?.disconnect();
            observer = null;
            if (video) {
              video.removeEventListener('leavepictureinpicture', detach);
              video.textTracks?.removeEventListener('change', schedule);
              video.textTracks?.removeEventListener('addtrack', watchTracks);
              for (const track of Array.from(video.textTracks || [])) track.removeEventListener('cuechange', schedule);
            }
            video = null;
            post('');
          };
          const watchTracks = () => {
            for (const track of Array.from(video?.textTracks || [])) track.addEventListener('cuechange', schedule);
            schedule();
          };
          const attach = element => {
            if (video === element) return;
            detach();
            video = element;
            // The player may draw its overlay only once captions are on, so
            // watch the player around the video rather than one overlay.
            const player = overlayFor(element)?.container
              || element.parentElement?.parentElement || element.parentElement || element;
            observer = new MutationObserver(schedule);
            observer.observe(player, { childList: true, subtree: true, characterData: true });
            // A video the page removes while it floats no longer passes its
            // events through the document, so hear it leave on the video.
            element.addEventListener('leavepictureinpicture', detach);
            element.textTracks?.addEventListener('change', schedule);
            element.textTracks?.addEventListener('addtrack', watchTracks);
            watchTracks();
          };
          document.addEventListener('enterpictureinpicture', event => {
            if (event.target instanceof HTMLVideoElement) attach(event.target);
          }, true);
          addEventListener('pagehide', detach);
        })();
        """#
}

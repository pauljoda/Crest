import Foundation
import WebKit

@MainActor
final class BrowserMediaSessionScriptMessageProxy: NSObject,
    WKScriptMessageHandler
{
    private let receive: @MainActor (WKScriptMessage) -> Void

    init(receive: @escaping @MainActor (WKScriptMessage) -> Void) {
        self.receive = receive
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        receive(message)
    }
}

@MainActor
enum BrowserMediaSessionContentBridge {
    static let messageHandlerName = "crestMediaSession"
    static let contentWorld = WKContentWorld.page

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserMediaSessionScriptMessageProxy {
        let proxy = BrowserMediaSessionScriptMessageProxy(receive: receive)
        userContentController.add(
            proxy,
            contentWorld: contentWorld,
            name: messageHandlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: contentWorld
            )
        )
        return proxy
    }

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestMediaSessionBridge) return;
          const session = globalThis.navigator?.mediaSession;
          const messageHandler = globalThis.webkit?.messageHandlers?.crestMediaSession;
          if (!session || !messageHandler) return;

          const documentIdentifier = globalThis.crypto?.randomUUID?.()
            || `${Date.now()}-${Math.random()}`;
          const actionHandlers = new Map();
          const playingElements = new Set();
          const knownElements = new Set();
          let fallbackPlaybackState = "none";
          let sequence = 0;
          let didObservePlayback = false;
          let didQualifyPlayback = false;
          let artworkGeneration = 0;
          let artworkSource = null;
          let artworkDataURL = null;
          let artworkAbortController = null;

          const cleanText = value => {
            if (typeof value !== "string") return null;
            const trimmed = value.trim();
            return trimmed && trimmed.length <= 512 ? trimmed : null;
          };

          const selectedArtworkSource = () => {
            const artwork = session.metadata?.artwork;
            if (!Array.isArray(artwork)) return null;
            let selected = null;
            let selectedArea = -1;
            for (const item of artwork) {
              const source = item?.src;
              if (typeof source === "string" && source.length <=
                  \#(BrowserMediaSessionArtworkPolicy.maximumSourceCharacters)) {
                const match = /^(\d+)x(\d+)$/i.exec(item?.sizes || "");
                const area = match ? Number(match[1]) * Number(match[2]) : 0;
                if (!selected || area > selectedArea) {
                  selected = source;
                  selectedArea = area;
                }
              }
            }
            return selected;
          };

          const encodedArtworkBlob = (canvas, type, quality) =>
            new Promise(resolve => canvas.toBlob(resolve, type, quality));

          const artworkDataURLFromBlob = blob => new Promise(resolve => {
            const fileReader = new FileReader();
            fileReader.onerror = () => resolve(null);
            fileReader.onload = () => resolve(fileReader.result);
            fileReader.readAsDataURL(blob);
          });

          const boundedOversizeArtwork = async (sourceBlob, generation) => {
            let bitmap;
            try {
              bitmap = await createImageBitmap(sourceBlob);
            } catch (_) {
              return null;
            }
            if (generation !== artworkGeneration) {
              bitmap.close?.();
              return null;
            }
            const scale = Math.min(
              1,
              \#(BrowserMediaSessionArtworkPolicy.maximumOversizePixelSize)
                / Math.max(bitmap.width, bitmap.height)
            );
            const canvas = document.createElement("canvas");
            canvas.width = Math.max(1, Math.round(bitmap.width * scale));
            canvas.height = Math.max(1, Math.round(bitmap.height * scale));
            const context = canvas.getContext("2d", { alpha: true });
            if (!context) {
              bitmap.close?.();
              return null;
            }
            context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
            bitmap.close?.();
            let encoded = await encodedArtworkBlob(
              canvas,
              sourceBlob.type === "image/jpeg" ? "image/jpeg" : "image/png",
              0.92
            );
            if (encoded?.size > \#(BrowserMediaSessionArtworkPolicy.maximumBytes)) {
              encoded = await encodedArtworkBlob(canvas, "image/jpeg", 0.86);
            }
            return encoded?.size <= \#(BrowserMediaSessionArtworkPolicy.maximumBytes)
              ? encoded : null;
          };

          const readBoundedArtwork = async (response, generation) => {
            const type = response.headers.get("content-type")?.split(";", 1)[0]?.toLowerCase();
            if (!["image/png", "image/jpeg", "image/webp"].includes(type)) return;
            const declaredLength = Number(response.headers.get("content-length"));
            if (Number.isFinite(declaredLength)
                && declaredLength > \#(BrowserMediaSessionArtworkPolicy.maximumInputBytes)) return;
            const reader = response.body?.getReader();
            if (!reader) return;
            const chunks = [];
            let total = 0;
            while (true) {
              const part = await reader.read();
              if (part.done) break;
              total += part.value.byteLength;
              if (total > \#(BrowserMediaSessionArtworkPolicy.maximumInputBytes)) {
                await reader.cancel();
                return;
              }
              chunks.push(part.value);
            }
            if (generation !== artworkGeneration) return;
            const sourceBlob = new Blob(chunks, { type });
            // Ordinary artwork crosses the bridge byte-for-byte. Rasterize only
            // when the original cannot fit the bounded native payload.
            const retainedBlob = sourceBlob.size
              <= \#(BrowserMediaSessionArtworkPolicy.maximumBytes)
              ? sourceBlob
              : await boundedOversizeArtwork(sourceBlob, generation);
            if (!retainedBlob || generation !== artworkGeneration) return;
            const dataURL = await artworkDataURLFromBlob(retainedBlob);
            if (generation !== artworkGeneration
                || typeof dataURL !== "string"
                || dataURL.length >
                    \#(BrowserMediaSessionArtworkPolicy.maximumDataURLCharacters)
                || !/^data:image\/(?:png|jpeg|webp);base64,/i.test(dataURL)) return;
            artworkDataURL = dataURL;
            post({});
          };

          const refreshArtwork = () => {
            const source = selectedArtworkSource();
            if (source === artworkSource) return;
            artworkSource = source;
            artworkDataURL = null;
            artworkGeneration += 1;
            artworkAbortController?.abort();
            artworkAbortController = null;
            if (!source) return;
            if (/^data:image\/(?:png|jpeg|webp);base64,/i.test(source)
                && source.length <=
                    \#(BrowserMediaSessionArtworkPolicy.maximumDataURLCharacters)) {
              artworkDataURL = source;
              return;
            }
            let url;
            try { url = new URL(source, globalThis.location.href); } catch (_) { return; }
            if (!["http:", "https:", "blob:", "data:"].includes(url.protocol)) return;
            const generation = artworkGeneration;
            artworkAbortController = new AbortController();
            fetch(url, {
              credentials: "same-origin",
              mode: "cors",
              signal: artworkAbortController.signal
            }).then(response => {
              if (!response.ok || generation !== artworkGeneration) return;
              return readBoundedArtwork(response, generation);
            }).catch(() => {});
          };

          const effectivePlaybackState = () => {
            const standard = session.playbackState;
            return standard === "playing" || standard === "paused"
              ? standard : fallbackPlaybackState;
          };

          const isAudible = () => {
            for (const element of playingElements) {
              if (!element.paused && !element.ended && !element.muted && element.volume > 0) {
                return true;
              }
            }
            return false;
          };

          const isMutedFlag = () => {
            if (knownElements.size === 0) return false;
            for (const element of knownElements) {
              if (!element.muted) return false;
            }
            return true;
          };

          const hasExplicitNonElementPlayback = () =>
            knownElements.size === 0 && session.playbackState === "playing";

          const post = extra => {
            const metadata = session.metadata;
            const playbackState = effectivePlaybackState();
            // Browsers do not surface every page that merely prepares Media
            // Session metadata. YouTube does that for muted hover previews and
            // promoted previews, neither of which is meaningful Now Playing.
            // Once real element playback has been audible, retain the session
            // while it pauses or mutes. A standards-driven Web Audio session
            // with no HTML media element can qualify through an explicit
            // MediaSession playbackState instead.
            const active = didQualifyPlayback || hasExplicitNonElementPlayback();
            try {
              messageHandler.postMessage({
                version: 1,
                documentIdentifier,
                sequence: ++sequence,
                location: String(globalThis.location.href).slice(0, 4096),
                invalidated: false,
                active,
                title: cleanText(metadata?.title),
                artist: cleanText(metadata?.artist),
                album: cleanText(metadata?.album),
                artworkDataURL,
                playbackState,
                audible: isAudible(),
                muted: isMutedFlag(),
                actions: Array.from(actionHandlers.keys()),
                ...extra
              });
            } catch (_) {}
          };

          const wrapProperty = property => {
            let owner = session;
            let descriptor;
            while (owner && !descriptor) {
              descriptor = Object.getOwnPropertyDescriptor(owner, property);
              owner = Object.getPrototypeOf(owner);
            }
            if (!descriptor?.get || !descriptor?.set) return;
            try {
              Object.defineProperty(session, property, {
                configurable: true,
                enumerable: descriptor.enumerable,
                get() { return descriptor.get.call(session); },
                set(value) {
                  descriptor.set.call(session, value);
                  queueMicrotask(() => {
                    if (property === "metadata") refreshArtwork();
                    post({});
                  });
                }
              });
            } catch (_) {}
          };

          const nativeSetActionHandler = session.setActionHandler;
          if (typeof nativeSetActionHandler === "function") {
            const observedSetActionHandler = new Proxy(nativeSetActionHandler, {
              apply(target, receiver, argumentsList) {
                const [action, handler] = argumentsList;
                const result = Reflect.apply(target, session, argumentsList);
                if (typeof action === "string") {
                  if (typeof handler === "function") actionHandlers.set(action, handler);
                  else actionHandlers.delete(action);
                  queueMicrotask(() => post({}));
                }
                return result;
              }
            });
            try {
              Object.defineProperty(session, "setActionHandler", {
                configurable: true,
                value: observedSetActionHandler
              });
            } catch (_) {}
          }

          wrapProperty("metadata");
          wrapProperty("playbackState");

          const observeMedia = event => {
            const media = event.target;
            if (!(media instanceof HTMLMediaElement)) return;
            didObservePlayback = true;
            if (event.type === "emptied") {
              knownElements.delete(media);
            } else if (knownElements.size < 32 || knownElements.has(media)) {
              knownElements.add(media);
            }
            switch (event.type) {
            case "play":
            case "playing":
              if (playingElements.size < 32 || playingElements.has(media)) {
                playingElements.add(media);
              }
              fallbackPlaybackState = "playing";
              break;
            case "pause":
            case "ended":
            case "emptied":
              playingElements.delete(media);
              fallbackPlaybackState = playingElements.size ? "playing" : "paused";
              break;
            default:
              break;
            }
            if (isAudible()) didQualifyPlayback = true;
            post({});
          };
          for (const type of ["play", "playing", "pause", "ended", "emptied", "volumechange"]) {
            document.addEventListener(type, observeMedia, { capture: true, passive: true });
          }

          const bridge = Object.freeze({
            emit() { post({}); },
            perform(action, expectedDocumentIdentifier) {
              if (expectedDocumentIdentifier !== documentIdentifier) return false;
              const handler = actionHandlers.get(action);
              if (typeof handler !== "function") return false;
              handler({ action });
              queueMicrotask(() => post({}));
              return true;
            },
            setMuted(muted, expectedDocumentIdentifier) {
              if (expectedDocumentIdentifier !== documentIdentifier) return false;
              const next = muted === true;
              let touched = false;
              for (const element of knownElements) {
                try {
                  element.muted = next;
                  touched = true;
                } catch (_) {}
              }
              queueMicrotask(() => post({}));
              return touched;
            }
          });
          Object.defineProperty(globalThis, "__crestMediaSessionBridge", {
            value: bridge,
            configurable: false,
            enumerable: false,
            writable: false
          });
          addEventListener("pagehide", () => {
            artworkAbortController?.abort();
            post({ invalidated: true, active: false });
          }, { once: true });
          queueMicrotask(() => {
            refreshArtwork();
            post({});
          });
        })();
        """#
}

import Foundation

enum BrowserPictureInPictureScript {
    static let source = #"""
        (() => {
          'use strict';
          if (globalThis.__crestPictureInPicture) return;
          const handler = globalThis.webkit?.messageHandlers?.crestPictureInPicture;
          if (!handler) return;
          const documentID = crypto.randomUUID?.() || `${Date.now()}-${Math.random()}`;
          const ids = new WeakMap();
          const interacted = new WeakSet();
          const knownVideos = new Set();
          const knownFrames = new Set();
          const observedRoots = new WeakSet();
          let nextID = 0;
          let scheduled = false;
          let lastState = '';
          let automatic = null;
          let parentAllows = window === top;
          const idFor = video => {
            if (!ids.has(video)) {
              ids.set(video, String(++nextID));
              for (const type of ['playing', 'pause', 'ended', 'emptied', 'loadedmetadata', 'resize',
                                  'enterpictureinpicture', 'leavepictureinpicture', 'webkitpresentationmodechanged']) {
                video.addEventListener(type, schedule);
              }
              video.addEventListener('leavepictureinpicture', () => {
                if (automatic?.video === video) automatic = null;
              });
            }
            return ids.get(video);
          };
          const send = payload => handler.postMessage({ documentID, ...payload });
          const connected = elements => {
            for (const element of elements) if (!element.isConnected) elements.delete(element);
            return Array.from(elements);
          };
          const videos = () => connected(knownVideos);
          \#(BrowserMediaPlayerPolicyScript.source)
          const candidate = video => {
            const bounds = video.getBoundingClientRect();
            const inViewport = bounds.bottom > 0 && bounds.right > 0
              && bounds.top < innerHeight && bounds.left < innerWidth;
            const eligible = parentAllows && !video.paused && !video.ended && video.readyState >= 2
              && video.videoWidth > 0 && video.videoHeight > 0
              && bounds.width >= 160 && bounds.height >= 90 && inViewport
              && !video.disablePictureInPicture && !video.controlsList?.contains('nopictureinpicture')
              && video.webkitSupportsPresentationMode?.('picture-in-picture') === true
              && !isDecorative(video) && hasPlayerControls(video, interacted.has(video));
            return { videoID: idFor(video), eligible,
              score: bounds.width * bounds.height + (interacted.has(video) ? 100000000 : 0) };
          };
          const isActive = video => document.pictureInPictureElement === video
            || video.webkitPresentationMode === 'picture-in-picture';
          const snapshot = () => {
            const found = videos();
            const candidates = found.map(candidate).filter(item => item.eligible)
              .sort((a, b) => b.score - a.score);
            return { kind: 'state', ...candidates[0], eligible: candidates.length > 0,
              active: found.some(isActive) };
          };
          const publish = () => {
            scheduled = false;
            publishFrameEligibility();
            const state = snapshot();
            const encoded = JSON.stringify(state);
            if (encoded === lastState) return;
            lastState = encoded;
            send(state);
          };
          const schedule = () => {
            if (scheduled) return;
            scheduled = true;
            setTimeout(publish, 100);
          };
          // The parent can see whether an iframe is decorative; a cross-origin
          // child cannot inspect that DOM. Propagate only this boolean, never media
          // URLs or page contents. Each hop validates the sending Window identity.
          const publishFrameEligibility = () => {
            for (const frame of connected(knownFrames)) {
              const bounds = frame.getBoundingClientRect();
              const allowed = parentAllows && !isDecorative(frame)
                && bounds.width >= 160 && bounds.height >= 90
                && bounds.bottom > 0 && bounds.right > 0
                && bounds.top < innerHeight && bounds.left < innerWidth;
              frame.contentWindow?.postMessage({ crestPiPFrame: 'visibility', allowed }, '*');
            }
          };
          addEventListener('message', event => {
            if (event.data?.crestPiPFrame === 'visibility' && window !== top && event.source === parent) {
              const allowed = event.data.allowed === true;
              parentAllows = allowed;
              lastState = '';
              schedule();
            }
            if (event.data?.crestPiPFrame === 'ready'
                && connected(knownFrames).some(frame => frame.contentWindow === event.source)) {
              publishFrameEligibility();
            }
          });
          const cancel = requestID => {
            if (automatic?.requestID !== requestID) return;
            automatic.cancelled = true;
            if (isActive(automatic.video)) automatic.video.webkitSetPresentationMode('inline');
          };
          const enter = (expectedDocumentID, videoID, requestID) => {
            if (expectedDocumentID !== documentID || document.pictureInPictureElement) return false;
            const video = videos().find(video => idFor(video) === videoID);
            if (!video || !candidate(video).eligible) return false;
            const request = { requestID, video, cancelled: false };
            automatic = request;
            try {
              video.requestPictureInPicture().then(() => {
                if (request.cancelled) {
                  video.webkitSetPresentationMode('inline');
                  return;
                }
                send({ kind: 'request', requestID, succeeded: true });
                publish();
              }, () => send({ kind: 'request', requestID, succeeded: false }));
              return true;
            } catch (_) { return false; }
          };
          const observeInteraction = event => {
            if (!event.isTrusted || (event.type === 'keydown' && ![' ', 'Enter', 'k', 'K'].includes(event.key))) return;
            for (const video of videos()) {
              let container = video;
              for (let depth = 0; container && depth < 4; depth++, container = parentOf(container)) {
                if (container === document.body || container === document.documentElement) break;
                if (event.composedPath().includes(container)) { interacted.add(video); break; }
              }
            }
            schedule();
          };
          for (const type of ['playing', 'pause', 'ended', 'emptied', 'loadedmetadata', 'resize',
                              'enterpictureinpicture', 'leavepictureinpicture', 'webkitpresentationmodechanged']) {
            document.addEventListener(type, schedule, true);
          }
          document.addEventListener('pointerdown', observeInteraction, true);
          document.addEventListener('keydown', observeInteraction, true);
          document.addEventListener('visibilitychange', () => { lastState = ''; schedule(); });
          addEventListener('resize', schedule);
          addEventListener('scroll', schedule, { passive: true, capture: true });
          addEventListener('pageshow', () => { lastState = ''; schedule(); });
          addEventListener('pagehide', () => send({ kind: 'removed' }));
          // Discover only inserted subtrees. Playback and layout changes inspect
          // the bounded media set rather than rescanning a large page's entire DOM.
          const observerOptions = { childList: true, subtree: true, attributes: true,
            attributeFilter: ['controls', 'autoplay', 'loop', 'muted', 'hidden', 'aria-hidden',
                             'disablepictureinpicture', 'role', 'class', 'style'] };
          const discover = (root, scannedRoots = new WeakSet()) => {
            if (!root.querySelectorAll) return;
            // A batch can report both an inserted ancestor and its descendants.
            // Their current subtrees already include every change in the batch.
            for (let ancestor = root; ancestor; ancestor = ancestor.parentNode) {
              if (scannedRoots.has(ancestor)) return;
            }
            connected(knownVideos);
            connected(knownFrames);
            const inspect = element => {
              if (element.matches?.('video') && knownVideos.size < 32) knownVideos.add(element);
              if (element.matches?.('iframe') && knownFrames.size < 64) knownFrames.add(element);
              if (element.shadowRoot && !observedRoots.has(element.shadowRoot)) {
                observedRoots.add(element.shadowRoot);
                mutationObserver.observe(element.shadowRoot, observerOptions);
                discover(element.shadowRoot, scannedRoots);
              }
            };
            inspect(root);
            let visited = 0;
            const elements = root.querySelectorAll('*');
            for (const element of elements) {
              if (++visited > 10000) break;
              inspect(element);
            }
            // A truncated scan must not suppress later records beyond its limit.
            if (elements.length <= 10000) scannedRoots.add(root);
          };
          const mutationObserver = new MutationObserver(records => {
            const scannedRoots = new WeakSet();
            for (const record of records) for (const node of record.addedNodes) discover(node, scannedRoots);
            if (knownVideos.size || knownFrames.size) schedule();
          });
          mutationObserver.observe(document, observerOptions);
          discover(document);
          globalThis.__crestPictureInPicture = Object.freeze({ enter, cancel, snapshot,
            emit() { lastState = ''; publish(); } });
          if (window !== top) parent.postMessage({ crestPiPFrame: 'ready' }, '*');
          schedule();
        })();
        """#
}

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
          const parentOf = element => element.parentElement || element.getRootNode()?.host;
          const isDecorative = video => {
            for (let element = video; element; element = parentOf(element)) {
              const style = getComputedStyle(element);
              if (element.hidden || element.inert || element.getAttribute('aria-hidden') === 'true'
                  || ['presentation', 'none'].includes(element.getAttribute('role'))
                  || style.display === 'none' || style.visibility !== 'visible'
                  || Number(style.opacity) === 0 || style.pointerEvents === 'none') return true;
            }
            return false;
          };
          const hasPlayerControls = video => {
            if (video.controls) return true;
            const videoArea = video.getBoundingClientRect().width * video.getBoundingClientRect().height;
            let container = parentOf(video);
            for (let depth = 0; container && depth < 6; depth++, container = parentOf(container)) {
              if (container === document.body || container === document.documentElement) break;
              const bounds = container.getBoundingClientRect();
              if (bounds.width * bounds.height > Math.max(videoArea * 6, 4000000)) break;
              // A lone "pause background animation" control is deliberately not a
              // player. Seek/volume sliders plus transport buttons identify a real
              // control surface without depending on the language of its labels.
              const exposed = control => {
                for (let element = control; element && element !== container; element = parentOf(element)) {
                  if (element.hidden || getComputedStyle(element).display === 'none') return false;
                }
                return true;
              };
              const buttons = Array.from(container.querySelectorAll('button, [role="button"]')).filter(exposed);
              const timeline = Array.from(container.querySelectorAll('input[type="range"], [role="slider"], progress')).some(exposed);
              if (buttons.length >= 2 && timeline) return true;
              // Players without a seek bar (live streams) can qualify after a real
              // click/key interaction and with multiple actual playback controls.
              if (interacted.has(video) && buttons.length >= 2) {
                const controls = Array.from(buttons).filter(button =>
                  /play|pause|mute|volume|fullscreen/i.test(
                    [button.getAttribute('aria-label'), button.title, button.textContent].join(' ')
                  ));
                if (controls.length >= 2) return true;
              }
            }
            return false;
          };
          const candidate = video => {
            const bounds = video.getBoundingClientRect();
            const inViewport = bounds.bottom > 0 && bounds.right > 0
              && bounds.top < innerHeight && bounds.left < innerWidth;
            const eligible = parentAllows && !video.paused && !video.ended && video.readyState >= 2
              && video.videoWidth > 0 && video.videoHeight > 0
              && bounds.width >= 160 && bounds.height >= 90 && inViewport
              && !video.disablePictureInPicture && !video.controlsList?.contains('nopictureinpicture')
              && video.webkitSupportsPresentationMode?.('picture-in-picture') === true
              && !isDecorative(video) && hasPlayerControls(video);
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
          const discover = root => {
            if (!root.querySelectorAll) return;
            connected(knownVideos);
            connected(knownFrames);
            const inspect = element => {
              if (element.matches?.('video') && knownVideos.size < 32) knownVideos.add(element);
              if (element.matches?.('iframe') && knownFrames.size < 64) knownFrames.add(element);
              if (element.shadowRoot && !observedRoots.has(element.shadowRoot)) {
                observedRoots.add(element.shadowRoot);
                mutationObserver.observe(element.shadowRoot, observerOptions);
                discover(element.shadowRoot);
              }
            };
            inspect(root);
            let visited = 0;
            for (const element of root.querySelectorAll('*')) {
              if (++visited > 10000) break;
              inspect(element);
            }
          };
          const mutationObserver = new MutationObserver(records => {
            for (const record of records) for (const node of record.addedNodes) discover(node);
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

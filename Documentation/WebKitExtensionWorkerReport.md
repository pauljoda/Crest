# WKWebExtension: a stopped background service worker is reported as loaded

**Platform:** macOS 27.0, Xcode 27.0 (27A5218g), the WebKit shipping with the
current release
**API:** `WKWebExtensionContext`, `WKWebExtensionController`
**Filed from:** Crest, a `WKWebView`-based browser that runs Chrome Web Store
and addons.mozilla.org extensions through `WKWebExtension`
**Measurements:** August 14–15, 2026

## Summary

After an MV3 extension's background service worker is stopped for idleness,
WebKit keeps the background *page* that registered it alive for a further
40–115 seconds. For that window the extension is in a half-loaded state:

1. `-[WKWebExtensionContext loadBackgroundContentWithCompletionHandler:]` calls
   its completion handler with no error and does no work — no page is
   constructed, no worker is started.
2. A `runtime` message sent from the extension's own popup is answered with
   `undefined` rather than restarting the worker to deliver it.

The MV3 contract is that events and messages are deliverable to listeners
registered by a stopped worker, with the worker restarted to receive them.
WebKit honours that contract once the background page is gone — measured
below, both for `tabs.onUpdated` and for `tabs.onCreated` — but not while the
page lingers. In that window the host app has no way to detect the state
either: there is no worker-liveness property, no background-unload API, and
`isLoaded` is context-level rather than worker-level.

## Observed sequence (unmodified signed Dark Reader 4.9.129 from the Chrome Web Store)

App launched at 04:11:16. Log via
`log show --predicate 'process == "Crest"' --info --debug`:

```
04:11:18.981  pageProxyID=128  WebPageProxy::constructor            ← background content
04:11:18.981  pageProxyID=128  WebPageProxy::loadServiceWorker: / loadData:
04:11:19.185  WebContent[86547] Created service worker 21
04:11:19.191  ServiceWorker::updateState: 21 state 0→1→2→3→4        ← installs and activates cleanly
04:11:22.163  pageProxyID=1151 WebPageProxy::loadRequest:           ← popup, worker ALIVE, works
04:11:24.300  WebProcessProxy::startServiceWorkerBackgroundProcessing [PID=86547]
04:11:24.300  WebContent[86547] SWContextManager::terminateWorker 21   (5.1s after activation)
04:11:24.300  ServiceWorker::updateState: 21 state 4→5
04:11:25.580  pageProxyID=2127 WebPageProxy::loadRequest:           ← popup opened in the window
04:11:25.638  [WebKit:Extensions] Uncaught exception in extension callback:
                TypeError: Cannot destructure property 'data' from null or undefined value
04:11:25.638  [WebKit:Extensions] Error recorded: WKWebExtensionContextErrorDomain Code=7
04:11:32.841  pageProxyID=2646 WebPageProxy::loadRequest:           ← again, same result
04:12:06.480  pageProxyID=128  WebPageProxy::close:                 ← window ends (42s wide here)
04:14:07.632  pageProxyID=3159 loadServiceWorker:                   ← loadBackgroundContent now works
04:14:07.674  WebContent[86547] Created service worker 696
04:14:08.685  pageProxyID=3175 WebPageProxy::loadRequest:           ← popup, no error
```

Between `terminateWorker 21` and `close:` on page 128 there is no
service-worker creation of any kind, despite two popups each sending an opening
`runtime` message. Four popup opens, four outcomes matching one rule exactly:
the popup works when the worker is alive, or when the background page is gone
so `loadBackgroundContent` genuinely reloads; it fails in between.

An earlier session showed the same shape with a 114-second window (worker
stopped 22:13:40.986, page closed 22:15:35.148).

The worker's termination is preceded in the same microsecond by
`WebProcessProxy::startServiceWorkerBackgroundProcessing` for the worker's web
process, which is the transition to that process hosting nothing but a service
worker. In this session it happened 2.1 seconds after the extension's popup
page — hosted in the same process — was closed.

## Events do restart an unloaded background, on the same build

The same fixture measured against a *fully* unloaded background shows WebKit
honouring the MV3 contract. An unpacked MV3 fixture registers
`chrome.tabs.onCreated` and `chrome.tabs.onUpdated` synchronously at the top
level and appends `Date.now()` to `chrome.storage.local` from each listener and
from its own startup, so a worker that started *at* an event is distinguishable
from an event queued until something else started one. `tabs` and `storage` are
granted in the permission snapshot the context is loaded with, so the first run
of the background is already able to record.

In this configuration WebKit unloads background content it considers idle at
**exactly 30.0 seconds** after the load, closing the page and the worker
together. Dispatching `-[WKWebExtensionController didChangeTabProperties:
forTab:]` with `.URL` and `.title` — a redundant notification carrying the
tab's real current values, nothing fabricated — 60 seconds after that:

```
09:12:59.170  pageProxyID=137  WebPageProxy::loadServiceWorker:      ← background content
09:12:59.232  WebContent[14154] Created service worker 62
09:13:29.234  pageProxyID=137  WebPageProxy::close:                  ← +30.0s, background unloaded
09:14:29.248  CrestWakeProbe properties dispatching changedProperties
09:14:29.283  pageProxyID=153  WebPageProxy::constructor             ← +35ms
09:14:29.286  pageProxyID=153  WebPageProxy::loadServiceWorker:      ← +38ms
09:14:29.361  WebContent[14713] Created service worker 71            ← +113ms
```

The fixture agrees from the inside: `starts` gained a second entry at
`…269379` and `updated` recorded `"url|title@…269379"` — the restarted worker
received the event that restarted it, 113 ms after dispatch.

`didOpenTab:` for a tab genuinely added to the session behaves the same way:

```
09:11:23.736  pageProxyID=76   WebPageProxy::loadServiceWorker:
09:11:23.798  WebContent[13576] Created service worker 34
09:12:53.771  CrestWakeProbe opened dispatching openedTab
09:12:53.778  pageProxyID=93   WebPageProxy::loadServiceWorker:      ← +7ms
09:12:53.874  WebContent[14113] Created service worker 43            ← +103ms
              fixture: created=[…173891], starts=[…083812, …173890]
```

The control — the same 90-second idle with nothing dispatched — records one
worker start and no events, and shows no page construction after the 30-second
unload:

```
09:09:48.224  pageProxyID=27   WebPageProxy::loadServiceWorker:
09:09:48.333  WebContent[13013] Created service worker 13
09:10:18.334  pageProxyID=27   WebPageProxy::close:                  ← +30.0s
09:11:18.287  CrestWakeProbe control dispatching none
09:11:23.500  CrestWakeProbe control read {"starts":[1786802988347]}
```

Reading the result opens one of the extension's own pages and reads
`chrome.storage.local` directly rather than messaging the background, so the
reading cannot be what restarted the worker; the control confirms it — no
second start appears there.

So the defect is specific: **the same event that restarts an unloaded
background does not reach a background whose page is still alive with a stopped
worker.** A host that could tell the two states apart could route around it;
none of the public API distinguishes them.

## The lingering-page window could not be reproduced outside a real session

Every attempt to reach the "worker stopped, page alive" state from an
XCTest host on this machine failed. WebKit there either kept the worker alive
or unloaded the page and the worker together at 30.0 seconds; the intermediate
state never occurred. Recorded so the next person does not repeat them:

| Attempt | Result |
| --- | --- |
| Idle 15s, ephemeral controller | Worker alive at +15s; event delivered with no restart |
| Idle 15s, persistent controller | Same |
| Idle 90s | Page and worker unloaded together at +30.0s, no separate `terminateWorker` |
| A real page loaded in an on-screen window on the same controller | No change |
| An extension page opened, sent the popup's opening `runtime` message, then destroyed | Worker served the message and stayed alive; no termination in the following 16s |
| The same, with the extension page on screen so its process held a foreground assertion | No change |

`NSPopover` cannot stand in for the popup here: a test host is not the active
application, the popover is never shown, and `closePopup()` on an unshown
popover leaves the popup document loaded — which is itself enough to keep the
worker from being reconsidered, since a live client page prevents it.

The window is therefore only observable in a real browsing session, which is
where every reading in the first section was taken.

## What the host app cannot do about it

- No public API reports whether background content is *running* as opposed to
  *loaded*. `WKWebExtensionContext.isLoaded` is context-level.
- No public API unloads background content, so the host cannot force
  `loadBackgroundContent` to do real work.
- Timing does not discriminate: an immediate completion means "worker alive" or
  "worker stopped, page lingering", identically.
- Dispatching a truthful `tabs` event does restart an unloaded background, but
  it is the same state `loadBackgroundContent` already handles, so it adds
  nothing inside the window.
- Unloading and reloading the whole context does force a restart, with the
  caveats below.

## Secondary issue: `unload` + `load` on the same context

Measured with an unpacked MV3 fixture that records `runtime.onInstalled`
reasons, its own worker starts, and a marker, all into `chrome.storage.local`,
reading through one of the extension's own pages.
`-[WKWebExtensionController unloadExtensionContext:]` followed by
`loadExtensionContext:` on the **same** `WKWebExtensionContext` instance — same
`uniqueIdentifier`, same `baseURL`, same granted permissions:

```
controller configured with `WKWebExtensionController.Configuration(identifier:)`
and a persistent WKWebsiteDataStore   (Crest's production configuration)

  before restart: {"marker":"set-before-restart","starts":[…701649]}
  after  restart: {"marker":"set-before-restart","starts":[…701649, …705869]}

controller configured with `.nonPersistent()`  (Crest's test/isolated configuration)

  before restart: {"marker":"set-before-restart","starts":[…735786]}
  after  restart: {"starts":[…740087]}
```

Two readings, each reproduced across runs:

- **Storage survives a restart in the persistent configuration.** The marker is
  intact afterwards and the restarted worker appends its start beside the
  original. An earlier measurement that reported storage loss was taken against
  a `.nonPersistent()` controller, where the whole store goes with the context;
  that result does not carry over to a shipping configuration.
- **`runtime.onInstalled` was not observed to fire at all** on this build — not
  on the first load and not on the restart, in either configuration. The
  fixture records the reason twice, once through a queued append and once
  through an unqueued `chrome.storage.local.set`, so a lost write is ruled out.
  An earlier ephemeral run recorded `reason=install` after a restart; this
  rerun did not reproduce it, and the discrepancy is unexplained.

One related WebKit behaviour worth separating out, because it cost a
measurement: **two `chrome.storage.local.set` calls in flight at once lose one
of their keys.** Writing `{a: …}` and `{b: …}` concurrently from the same
worker leaves only the later key present. Serializing the writes fixes it. Each
`set` is specified to merge into the existing record rather than replace it.

## Asks

1. Restart a stopped background service worker when a `runtime` message or an
   extension event needs to reach a listener it registered, including while its
   background page is still alive. Event delivery already restarts a fully
   unloaded background; the lingering page is the only case that fails.
2. Failing that, make `loadBackgroundContent` restart a stopped worker rather
   than reporting success against one, or expose worker liveness so a host can
   tell.
3. Provide a supported restart-in-place with defined semantics for
   `runtime.onInstalled`.
4. Make concurrent `chrome.storage.local.set` calls merge rather than drop
   keys.

## Reproducing

Both instruments live in the macOS test target and are skipped unless asked
for, because each run idles past WebKit's background unload:

- `CrestTests/BrowserExtensionBackgroundWakeExperimentTests.swift` — event
  wake, delivery, and the no-event control.
- `CrestTests/BrowserExtensionBackgroundRestartMeasurementTests.swift` —
  `unload` + `load` against storage and `onInstalled`.

```
touch /tmp/CrestRunBackgroundWakeExperiment            # or CREST_RUN_BACKGROUND_WAKE_EXPERIMENT=1
touch /tmp/CrestWakePersistentStore                    # persistent store; omit for ephemeral
xcodebuild -project Crest.xcodeproj -scheme Crest \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:CrestTests/BrowserExtensionBackgroundWakeExperimentTests test
```

Each run stamps the unified log under the subsystem
`com.pauldavis.crest.wake-experiment`, so its markers interleave with WebKit's
own lines:

```
log show --start <run start> --info --debug --predicate \
  'process == "Crest" AND (eventMessage CONTAINS "CrestWakeProbe"
   OR eventMessage CONTAINS "Created service worker"
   OR eventMessage CONTAINS "terminateWorker"
   OR eventMessage CONTAINS "WebPageProxy::close"
   OR eventMessage CONTAINS "loadServiceWorker")' --style compact
```

## What Crest ships in the meantime

`BrowserExtensionPopupBackgroundWarmUp` asks for background content and
presents the popup once that call reports back or a 1.5-second deadline passes.
That is honest everywhere except inside the window described above, where
`loadBackgroundContent` reports success against a stopped worker. Nothing
app-side closes that gap: dispatching a tab event alongside the warm-up was
measured and reaches only the state the warm-up already handles, and restarting
the context is too blunt for a popup click. See
`Documentation/ExtensionCompatibility.md` for the shipped behaviour.

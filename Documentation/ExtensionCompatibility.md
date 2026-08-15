# Extension compatibility

Crest treats extension compatibility as a measured runtime result, not a
promise based only on a manifest. A package can verify, install, and load while
one of its optional or background features still reaches an API WebKit does not
implement.

## Public lead

**Install most standards-based Chrome extensions** directly from their Chrome
Web Store pages, and **most Firefox extensions** directly from their
addons.mozilla.org pages. Compatibility varies where an extension depends on
browser-specific APIs or a native companion.

Do not publish a blanket claim that all Chrome or all Firefox extensions work.

## Product behavior

- The Chrome Web Store page opens a native Crest review sheet. Crest verifies
  the signed CRX3 package, shows requested permissions and website access, and
  installs the extension into the selected Space.
- Extension installations remain **per Space and per device**. Permissions,
  storage, enablement, website access, and pinning do not silently cross into
  another Space or device.
- Crest hosts action popups, options pages, extension keyboard commands, and
  pinned actions where WebKit supports the APIs they use. Opening an options
  page focuses the one already open in that Space instead of adding another.
- A secondary click on a pinned extension button or a site-popover extension
  action opens that extension's own menu items and commands, alongside
  Extension Settings and pinning.
- Invoking an extension's keyboard command counts as the user gesture that
  grants `activeTab`, matching Chrome and Safari.
- `tabs.onUpdated` reports Crest's loading and reader-mode transitions, not only
  title, URL, and pinned changes.
- Extension background content and popups are inspectable in Web Inspector under
  the extension's display name.
- An unpacked extension keeps one identity across imports, derived from its
  manifest `key` when it has one and otherwise from its source folder. Importing
  the same folder again reloads it in place and keeps its pinning, permissions,
  command shortcuts, and stored data.
- Runtime failures are persisted with the extension and shown as **Needs
  attention** with a plain-language impact. JavaScript errors stay collapsed
  under **Technical Details**.
- Known package-specific limits appear before installation, remain visible in
  Extensions settings, and replace the green success treatment with **added
  with limited compatibility** after installation.

## Updates

Crest records where every installation came from, and that recorded source is
what decides whether it can be updated.

- **Chrome Web Store installations** are updatable. The registry row for one
  carries its verified extension ID, its store page, the SHA-256 of the
  package that was installed, and the pinned publisher-key hash.
- **Unpacked extensions** are never updated. There is no store identity to
  verify a replacement against, which is the same reason they are ineligible
  for native messaging.
- **Extensions loaded from an installed app** are not updated by Crest. They
  belong to the host application and change when it does.

### What a pass does

1. Crest asks Google's extension endpoint (`response=updatecheck`) which
   version it currently publishes. This is a few hundred bytes of XML, not a
   package, so a pass over a dozen installations does not download anything.
2. It compares that version against the installed version numerically, one
   dot-separated component at a time, so `1.10` counts as newer than `1.9`. A
   version string Crest cannot parse never triggers a replacement.
3. Only when the store's version is genuinely newer does Crest download the
   package — through its own pinned redirect endpoint, **not** the `codebase`
   URL from the update-check answer. A tampered answer therefore cannot
   redirect an update at a package of someone else's choosing.
4. The download runs the ordinary installation path: CRX3 signature
   verification against the pinned Chrome Web Store publisher key, an
   extension-identity cross-check, staging, load, and rollback to the previous
   package if any step fails.

A replacement preserves pinning, permission and website-access decisions,
keyboard-shortcut overrides, and the original install date. Each Space updates
its own copy of an extension independently.

### Settings

**Extensions** settings carries an **Updates** section: a switch for automatic
updates, a **Daily / Weekly / Every Two Weeks** cadence, a **Check for Updates
Now** action, and the time of the last check. The default is weekly and
enabled. The cadence is a single browser-wide setting rather than a per-Space
one, so two Spaces holding the same extension do not double the store traffic.

The schedule starts only after launch restoration has finished loading the
installed extensions, and a pass that fails for every extension — the shape of
being offline — retries in an hour rather than waiting out the full cadence.

### Extensions that are switched off

A disabled installation is deliberately skipped. Applying an update means
loading the replacement into a live WebKit context, which would silently
re-enable something that was switched off, and a package that is not running
is not exposed to anything either. A disabled extension rejoins the cadence on
the first pass after it is switched back on.

### Live check

`BrowserChromeWebStoreTests.testLiveUpdateCheckAnswersTheCurrentPublishedVersionWhenEnabled`
verifies the real response shape against Google's endpoint. Like the package
audit it is opt-in, behind `CREST_RUN_CHROME_STORE_INTEGRATION=1`, because it
depends on an external service. The ordinary gate parses recorded fixtures
instead.

## Deliberate concept mismatches

Some WebExtension capabilities describe a browser Crest is not. These are left
unimplemented on purpose rather than faked:

- **Closing or restaging a window.** A Space is not an operating-system window,
  so `windows.remove` and `windows.update` state changes are refused. Reading a
  window's frame, screen, and state is supported.
- **Tab audio.** Crest tracks no per-tab audio state, so `mutedInfo` and
  `audible` are not reported and muting is unavailable.
- **Parent tabs.** Crest records no opener relationship between tabs.
- **New tab page override.** `chrome_url_overrides.newtab` is not honored. A new
  tab on macOS opens Crest's command palette rather than loading a page, so
  there is no URL for an extension to replace.

## Native companion distribution boundary

- Ordinary WebExtensions can use APIs implemented by WebKit.
- Crest for Mac supports Chrome native messaging for verified
  Chrome Web Store installations. It discovers registered Chrome hosts,
  validates the manifest's exact `allowed_origins` entry against the verified
  extension ID, exchanges Chrome's little-endian framed JSON, and supports both
  one-shot `sendNativeMessage` calls and persistent `connectNative` ports.
- Unpacked extensions are never eligible for native messaging because their
  identity is not store-verified.
- Safari app-extension native handlers are not portable to Crest. When a
  standards-based WebExtension or Chrome Web Store version is available, use
  that version instead.
- Safari content blockers and legacy Safari App Extensions are not
  WebExtensions and cannot be hosted by Crest.
- Apple gates the iCloud Passwords helper separately. Its parent launch
  constraint requires the managed
  `com.apple.developer.web-browser.public-key-credential` entitlement (or an
  explicitly listed browser identity). Crest has requested that capability,
  but the current signature does not contain it.

## Validated installation paths

- **Chrome Web Store:** signed CRX3 verification, native review, per-Space
  installation, background load, action popup, options and command routing,
  pinning, permission management, status reporting, and removal are covered.
- **Firefox Add-ons:** listing resolution through Mozilla's public API,
  digest/size/identity verification, native review, per-Space installation,
  background load, and removal are covered. Native messaging is not available
  to this path.
- **Unpacked WebExtension:** manifest inspection, permission review, isolated
  per-Space installation, runtime loading, and removal are covered. Native
  messaging remains unavailable to this path.
- **Signed Safari Web Extension app:** Crest can discover and load an ordinary
  WebExtension component through **Scan for Apps** or **Choose App**. This does
  not make a third-party Safari native handler portable.
- **Crest for Mac native messaging:** regression coverage includes a real child
  native-host process exchanging Chrome-framed JSON and a real
  `WKWebExtension` background script reaching Crest's native-messaging delegate
  with its verified Chrome extension ID.

## 1Password live validation

The signed Chrome Web Store package for 1Password 8.12.30.21 completed the
following path in Crest for Mac on August 10, 2026:

1. **Add to Crest** opened Crest's native review sheet.
2. The extension installed and appeared as **Running**.
3. Its welcome and setup interface rendered.
4. **Sign in** opened a normal Crest tab at `my.1password.com`.
5. Unified logs verified that Crest's native-messaging bridge launched
   `/Applications/1Password.app/Contents/MacOS/1Password-BrowserSupport`.
6. Adding `/Applications/Crest.app` in **1Password → Settings → Browser**
   displayed and completed 1Password's explicit browser-authorization review.

The final account handoff exposed a distribution boundary. A full bidirectional
native-message trace showed the extension sending `NmRequestAccounts`, followed
by 1Password's helper returning `BrowserVerificationFailed` with
`BrowserSignatureInvalid`. The tested Crest build used an Apple Development
certificate. Removing the debug entitlement was necessary for a hardened
Release build, but did not make that development certificate acceptable to
1Password.

This proves installation, startup, normal navigation, persistent native-port
transport, companion launch, and the trusted-browser review UI. It does **not**
prove unlock or autofill. Those require the production-signed Crest release,
installed in `/Applications`, followed by a fresh 1Password browser
authorization. The Developer ID identity is now installed; the final signed,
notarized pairing validation remains outstanding.

Official references:

- <https://support.1password.com/additional-browsers/>
- <https://help.kagi.com/orion/browser-extensions/1password.html>

### 1Password for Safari is not a fallback

The installed `1Password for Safari.app` WebExtension resources can load, but
its bundled Safari native handler cannot be created by Crest. Its
`runtime.sendNativeMessage` call is rejected. Use the verified Chrome Web Store
extension with the official Crest for Mac release instead.

## iCloud Passwords live validation

The signed Chrome Web Store package for iCloud Passwords 3.3.0 verifies and
installs. Crest applies an exact-extension compatibility layer for WebKit APIs
the package expects but WebKit does not expose:

- `webNavigation.onHistoryStateUpdated`
- `webNavigation.onTabReplaced`
- `privacy.services` browser settings

With that layer, the service worker reached clean initial startup in the signed
package audit. This only preserves ordinary page-load behavior; the missing
history and tab-replacement events mean single-page-app refresh behavior remains
limited.

The native password workflow is currently blocked. In a live Direct build, the
action popup reported that it could not connect to its helper application. The
Apple system helper did not launch under Crest. Its signed parent launch
constraint accepts browsers carrying Apple's managed **Web Browser Public Key
Credential Requests** entitlement or an explicitly listed Chrome-family
identity. The tested Crest signature has neither.

Crest now warns before installation, uses an orange limited-compatibility
result after installation, and keeps the explanation in Extensions settings.
The capability request is pending. After Apple grants it, the next validation
gate is a newly provisioned Direct build followed by pairing, unlock, save, and
autofill tests. Direct distribution by itself does not bypass Apple's helper
constraint.

Official reference:

- <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential>

## Dark Reader live validation

Dark Reader 4.9.129 installs, loads, and restores from its **unmodified signed
package**. Crest carries no Dark Reader-specific code.

Two earlier Crest compatibility layers were removed:

- A manifest rewrite that deleted `background.service_worker`, dropped
  `preferred_environment`, and substituted a nonpersistent `background.scripts`
  page. It existed because an older WebKit preferred the service worker and tore
  it down while Dark Reader's IndexedDB-backed startup was still in flight.
- A literal patch of the extension's own `ui/popup/index.js`, which wrapped its
  first `chrome.runtime.sendMessage` call in a retry loop so a reopened popup
  could survive a background that had not restarted yet.

Neither is needed on the WebKit shipping with the current macOS release. The
signed package now completes its own service-worker startup, attaches to
ordinary granted pages as `data-darkreader-mode="dynamic"`, and answers the
popup's opening handshake. The shipped 4.9.129 manifest declares only
`background.service_worker`; it no longer offers the document-environment
alternative the rewrite used to select.

Removing the rewrite also keeps the runtime package byte-identical to the
verified CRX3 payload. Dark Reader loads directly from its stored signed
archive instead of an expanded, edited copy in a temporary directory.

The popup's earlier "stuck on the loader" behavior is corrected in Crest's own
action path rather than in the extension. A user-invoked toolbar or pinned
action presents the popup directly against the control that was clicked, and
closing an open popup calls WebKit's `closePopup()` so the popup web view is
unloaded instead of merely hidden. A hidden-but-loaded popup document is what
made a reopened popup wait on a handshake that had already been answered.

Crest calls `loadBackgroundContent` before presenting a popup, and presents the
popup only once that call reports back or a 1.5-second deadline passes.

That reverses an earlier decision, recorded here on August 13, 2026, that WebKit
restarts an evicted nonpersistent background on its own when the popup document
sends its first `runtime` message. It does not. In an ordinary session on
August 14, 2026, Dark Reader's background service worker was started at launch,
terminated 5.6 seconds later, and never restarted; a popup opened 21 seconds
after that had its opening `ui-bg-get-data` message answered with nothing:

```
22:13:35.367 [WebKit:ServiceWorker] Created service worker 16 in process PID 48546
22:13:40.986 [WebKit:ServiceWorker] SWContextManager::terminateWorker 16
22:14:02.052 [WebKit:Extensions]    Uncaught exception in extension callback:
                                    TypeError: Cannot destructure property 'data'
                                    from null or undefined value
22:14:02.052 [WebKit:Extensions]    Error recorded: Error Domain=
                                    WKWebExtensionContextErrorDomain Code=7
```

Dark Reader's popup reads the reply as `({data, error}) => …`, so an empty
answer throws inside the extension callback, the promise the popup awaits never
settles, and the popup stays on "Loading, please wait" for the rest of the
session. Its content scripts wait on the same background, so granted pages keep
whatever partial styling they were left with. Reading
`WKWebExtension.Action.popupPopover` preloads the popup document immediately, so
Crest unloads that preload with `closePopup()` and presents a popup that is
loaded only after the background is running.

The deadline is required rather than defensive: when background content
genuinely fails to load, WebKit never invokes `loadBackgroundContent`'s
completion handler at all, so waiting on it alone would leave a broken
extension's toolbar button inert. Background failures still reach people through
`WKWebExtensionContext.errors` and its `errorsDidUpdateNotification`, which Crest
persists into the extension's summary and shows as **Needs attention**.

`BrowserExtensionPopupBackgroundWarmUpTests` pins the three outcomes — loaded
first, deadline first, and both.
`BrowserExtensionControllerPoolTests.testToolbarPopupIsPresentedAfterItsBackgroundContentIsAskedFor`
pins the ordering against a real unpacked extension: it fails when the popover
is shown inside the call that asked for it.
`BrowserExtensionActionPopupLiveTests.testLiveDarkReaderPopupCompletesAfterItsBackgroundIsEvicted`
drives the real presentation path after a 45-second idle.

### Where the warm-up is still lied to, and why nothing else ships

The warm-up is honest everywhere except one window. WebKit stops an idle
service worker while keeping the background page that registered it alive for
another 40–115 seconds, and inside that window `loadBackgroundContent` reports
success without starting anything, so the popup is presented against a
background that cannot answer. Crest ships no second mechanism for it, because
the two candidates were measured and both fail on their own terms:

- **Dispatching a truthful `tabs` event alongside the warm-up.** Measured on
  August 15, 2026: `didChangeTabProperties` and `didOpenTab` both restart a
  background WebKit has *fully* unloaded — a new background page and worker 35
  and 113 milliseconds after dispatch, with the restarted worker receiving the
  event — but that is the state `loadBackgroundContent` already handles. The
  lingering-page window could not be reached from a test host at all, so
  nothing about it would be shipped on evidence.
- **Restarting the context.** `unload` + `load` does force a real restart, and
  the extension's `chrome.storage.local` survives it in the shipping
  persistent configuration. It is still too blunt for a popup click: it
  restarts every part of the extension, and `runtime.onInstalled` semantics
  across it are undefined. Commit `eb335b57` shipped a recovery on this and was
  reverted the same day in `c1fc2c35`.

The standing posture is therefore the warm-up, a WebKit bug report, and saying
so plainly: an extension clicked during that window can strand its popup until
the background page is torn down, after which it recovers on its own.
`Documentation/WebKitExtensionWorkerReport.md` carries the full measurements,
the log correlations, and the reproduction instructions.

### Why this covers popups and not content scripts

An extension's content scripts wait on the same background, and Dark Reader's
leave a granted page part-styled while they do. Crest does not warm the
background for them, because there is nothing to warm it *between*:
`WKWebExtensionControllerDelegate` has no callback on the content-script side at
all. Its two messaging methods — `sendMessage:toApplicationWithIdentifier:` and
`connectUsingMessagePort:` — are the native-messaging seam between the extension
and the host app, not the seam between a content script and its background.
WebKit injects content scripts and carries their `runtime` traffic entirely
inside its own machinery, so no app-side call can be placed in that path.

The popup is different in kind: it is the one background-dependent surface whose
creation Crest itself triggers, in a method WebKit hands it, so Crest can order
the two. The only lever that would reach content scripts is calling
`loadBackgroundContent` speculatively — on every navigation into a tab any
enabled extension can read — which would keep every nonpersistent background
permanently awake and is the decision a manifest makes with
`persistent`/`background.page`, not one a host app should make on an extension's
behalf.

If pages keep rendering against a stopped background after this change, that is
the content-script half of the same WebKit behavior, and it needs an answer in
WebKit rather than in Crest.

Evidence, gathered August 13, 2026:

- The opt-in live regression
  `BrowserChromeWebStoreTests.testLiveDarkReaderPackageVerifiesInspectsAndLoadsWhenEnabled`
  downloads the current signed package, installs it, and asserts live page
  attachment plus a popup that leaves its loader, survives close and reopen, and
  survives a 45-second idle long enough for the nonpersistent background to be
  evicted. It passed every run against the unmodified package, including three
  consecutive eviction runs.
- A throwing background worker and a missing background script both leave
  `loadBackgroundContent` silent past ten seconds while
  `WKWebExtensionContext.errors` correctly reports "The background content
  failed to load due to an error." along with the JavaScript error.

## Popular-extension audit

The following signed Chrome Web Store packages were audited on August 10, 2026.
Each package verified, installed into an isolated Space, and loaded. "Loads
cleanly" means no startup error was observed; it does not certify every account,
site, popup, update, or optional workflow.

| Extension | Version tested | Initial result | Measured boundary |
| --- | --- | --- | --- |
| Dark Reader | 4.9.129 | Loads cleanly | Installs unmodified; live page attachment and popup reopen verified separately |
| uBlock Origin Lite | 2026.804.1652 | Loads cleanly | Declarative Net Request package loaded without a startup error |
| 1Password | 8.12.30.21 | Partial / production-signature gated | Setup, sign-in navigation, persistent native messaging, BrowserSupport launch, and browser-authorization UI were verified; the Apple Development build was rejected as `BrowserSignatureInvalid`, so production-signature pairing and autofill remain unverified |
| SponsorBlock | 6.1.6 | Loads cleanly | No manifest or startup runtime error observed |
| Bitwarden | 2026.7.0 | Partial / experimental | The signed package and core worker load; notification-click handling is unsupported by WebKit, and account unlock/autofill has not been certified |
| Grammarly | 14.1319.0 | Partial / experimental | Managed storage plus cookie and telemetry limits are reported |
| React Developer Tools | 7.0.1 | Partial / experimental | `chrome.scripting.ExecutionWorld.ISOLATED` is unavailable |
| Tampermonkey | 5.5.0 | Partial / experimental | WebKit rejects its `tabs.onUpdated` startup registration. Crest now reports loading and reader-mode changes to that event, but the rejected registration is a WebKit boundary and is unchanged |
| iCloud Passwords | 3.3.0 | Blocked / Apple entitlement pending | The worker loads with exact-package WebKit shims, but Apple's password helper rejects the current unsigned-capability parent; pairing and autofill require the managed browser credential entitlement |

## Firefox extensions from addons.mozilla.org

Firefox is in several respects a better native fit for WebKit than Chrome.
`WKWebExtension` accepts Manifest V2 with a persistent background page, and the
promise-based `browser.*` namespace Firefox extensions are written against is
what WebKit implements natively. The work is therefore concentrated in
acquisition and provenance rather than in runtime shims.

### How acquisition is verified

A Firefox add-on is a plain ZIP. Unlike a CRX3 it carries no identity in its own
container, so nothing about the file alone proves who published it. The binding
comes from the listing instead:

1. Crest resolves the add-on through
   `https://addons.mozilla.org/api/v5/addons/addon/{slug}/`, which publishes the
   gecko `guid`, the current version, the exact download URL, its byte count,
   and its SHA-256 digest.
2. The listing must describe a public, non-disabled add-on of type
   `extension`. Themes, dictionaries, and language packs are refused.
3. The download URL must be `https` on `addons.mozilla.org`, and the response's
   final URL must still be on that host after any redirect. As measured on
   August 13, 2026, AMO serves the XPI directly from `addons.mozilla.org` with
   no redirect and no separate CDN host.
4. The downloaded bytes must reproduce the published SHA-256 digest and byte
   count exactly, under a 64 MiB ceiling.
5. The archive's central directory must contain `manifest.json` plus Mozilla's
   JAR signing artifacts — `META-INF/mozilla.rsa`, `META-INF/mozilla.sf`, and
   `META-INF/manifest.mf`. A self-built or side-loaded archive is refused.
6. If the add-on's own `manifest.json` declares a
   `browser_specific_settings.gecko.id`, it must equal the listing's `guid`. The
   key is optional, because AMO assigns an identity at signing when an author
   omits it.

The registry re-validates provenance on every write: the record's identity must
be the source's gecko identity, the stored store URL must still parse back to
the same slug, and the digest and version must remain well formed.

### Hardening follow-up: full Mozilla signature verification

Crest currently requires Mozilla's signature to be **present** but does not
cryptographically verify it. Full verification means decoding the PKCS#7
`SignedData` in `META-INF/mozilla.rsa` with `CMSDecoder`, evaluating its chain
against a pinned Mozilla AMO production root rather than the system trust store,
then checking `mozilla.sf`'s digest of `manifest.mf` and walking every per-entry
digest in `manifest.mf` against the inflated archive contents.

That was deliberately not shipped in this pass. A partial version — verifying
the CMS blob without walking the manifest digests — would prove nothing about
the payload while implying that it did. Until the full chain lands, integrity
rests on TLS to `addons.mozilla.org` plus the digest and byte count that host
published for the file, which is a real binding but a strictly weaker one than
the CRX3 path's signature verification.

### Identity and native messaging

Firefox add-ons receive a Space-namespaced runtime identifier
(`<gecko-id>.space.<space-uuid>`), like every non-Chrome source. Only verified
Chrome Web Store installations keep their bare store identity, because that
identity is what Chrome native-messaging hosts match in `allowed_origins`.

Native messaging is therefore blocked for Firefox add-ons. An add-on requesting
`nativeMessaging` is refused before installation with a plain-language reason.

### Expected gaps

WebKit reports Firefox-only manifest keys as errors and warnings rather than
refusing the package. Those surface in the review sheet's **WebKit Compatibility
Warnings** section and are recorded with the installation; they do not block
installation. Expect the following to be unavailable:

- `sidebar_action` sidebars
- `contextualIdentities` container tabs
- `theme` and dynamic theme APIs
- Blocking `webRequest` request cancellation and modification
- `browserSettings`
- `menus` beyond what WebKit's `contextMenus` implements

### Firefox package audit

The following listings were acquired, verified, installed into an isolated
Space, and loaded on August 13, 2026 by
`BrowserMozillaAddonsTests.testLiveFirefoxAddonVerifiesInspectsAndLoadsWhenEnabled`.
"Loads cleanly" means no startup error was observed; it does not certify every
account, site, popup, update, or optional workflow.

| Extension | Version tested | Initial result | Measured boundary |
| --- | --- | --- | --- |
| Dark Reader | 4.9.129 | Loads cleanly | No manifest or runtime error observed, and no unsupported API reported |
| uBlock Origin | 1.73.0 | Partial / experimental | WebKit rejects an entry in its `commands` manifest entry, and its background script fails at `vAPI.getURL('').slice`. Its `webRequest` blocking model is not implemented by WebKit |
| Bitwarden | 2026.7.0 | Partial / experimental | The signed package and core worker load; notification-click handling is unsupported by WebKit. The Firefox build does not request `nativeMessaging`, so it is not blocked before installation |

The audit is opt-in for the same reason the Chrome one is: it downloads current
external packages and is not deterministic enough for the ordinary unit-test
gate. Run it with `TEST_RUNNER_CREST_RUN_AMO_INTEGRATION=1`, or by creating
`/tmp/CrestRunAMOIntegration`.

## Chrome Web Store origin and action popups

Chrome treats `chromewebstore.google.com` as a protected origin. It withholds
host access there, refuses content-script injection, and hides the tab's URL
from extensions that did not request the `tabs` permission.

**Crest does not protect that origin.** An extension holding `*://*/*` receives
host access on the store page, `tabs.get` reports the store URL, and
`scripting.executeScript` succeeds against it. This was measured, not assumed:
on a store tab, `chrome.tabs.get` returns the full URL and an injected
`world: "MAIN"` function returns `https://chromewebstore.google.com/`.

Crest's own **Add to Crest** bridge is unrelated to this. It is a `WKUserScript`
in a private content world, not a WebExtension, so extension host permissions
neither enable nor restrict it.

### Dark Reader is not affected by that mismatch

A maintainer report described Dark Reader 4.9.129's popup hanging on
"Loading, please wait" whenever the active tab was on the store, for an
extension loaded by launch restoration. **That did not reproduce**, and the
extension's own source explains why it should not:

- Dark Reader carries its own hardcoded restricted list in `canInjectScript`
  (`background/index.js`). Both branches of its only browser conditional reject
  `https://chrome.google.com/webstore` and `https://chromewebstore.google.com/`,
  so the list is **not** browser-gated. The package defines no `isChromium` or
  `isSafari` binding at all, so Crest's Safari-shaped user agent takes the same
  path Chrome takes.
- That list only labels the tab. It drives the popup's "This page is protected
  by browser" text and suppresses theming. It gates nothing asynchronous.
- The popup awaits exactly three promises, and active-tab information is a
  field of the `ui-bg-get-data` reply rather than a separate request. Nothing
  in the popup or background awaits a content-script response.

Measured on a live signed package, popup ready time by active tab and load
path, on the tree that carries the action-popup unload rework, the tab-adapter
expansion, and the window-geometry and reader-mode relays:

| Active tab | Fresh install | Launch restoration |
| --- | --- | --- |
| `https://example.com/` | renders, ~80 ms | renders, ~80 ms |
| `https://chromewebstore.google.com/` | renders "protected", ~86 ms | renders "protected", ~85 ms |

Every host call Dark Reader's `collectData` awaits settles in 0–2 ms on both
origins, including `tabs.query`, `tabs.get`, `scripting.executeScript`, and
`storage.local.get`. MV3 cold start after launch restoration reaches a rendered
popup, so restoration does not need a forced background load.

The same matrix passes through Crest's real presentation path — the
`NSPopover` from `action.popupPopover`, including a toggle closed that calls
`action.closePopup()` to unload the popup web view, followed by a reopen. A
popup that survived only its first load would be caught there.

### Diagnosing a popup stall on a device

Because the extension reports nothing when this fails, a stuck popup has to be
told apart from a stalled host call by hand. Contexts are inspectable, so open
Web Inspector on the popup and run:

```js
chrome.runtime.sendMessage({type: "ui-bg-get-data"},
    (r) => console.log(r, chrome.runtime.lastError));
```

- An `undefined` reply with a `lastError` means the background never answered,
  so inspect the background page rather than the popup.
- **Total silence** — no log line at all — means the background is parked
  inside a host call. Inspect the background context and check which `chrome.*`
  promise inside `collectData` is still pending.
- A normal reply means the popup rendered from stale state, which is a
  different problem.

Capture the active tab's URL at the same time. A stall that only appears on one
origin points at a host call whose cost depends on the page rather than at the
popup lifecycle.

### Why this extension turns any host stall into a permanent hang

The failure mode is worth recording even though Crest did not cause it here.
Dark Reader's request path has no safety net at either end:

- The background answers `ui-bg-get-data` with `collect().then(sendResponse)`
  and **no `.catch`**, after returning `true` to hold the message channel open.
  Any rejection on that path means the response is simply never sent.
- The popup's `sendRequest` wraps `chrome.runtime.sendMessage` with **no
  timeout and no `runtime.lastError` check**, and destructures the reply
  directly. An `undefined` reply throws inside the promise executor, so the
  promise neither resolves nor rejects.
- Its three-second loader fallback lives inside the component tree that the
  failed request prevented from rendering, so it can never fire.

Consequently any host `chrome.*` call that stalls or throws on that one path
strands the popup on its startup loader with no error surface. A popup stuck on
"Loading, please wait" with no error after three seconds means the request never
completed, not that the extension detected a problem.

## wBlock

wBlock is a hybrid. Its toolbar and userscript portion use Safari Web
Extensions, but its primary blocker uses five Safari-only content-blocker
extensions. Crest cannot reproduce the core wBlock blocking behavior and must
not market wBlock as fully supported.

## Distribution readiness

Native companion messaging is implemented in Crest for Mac. The GitHub release
workflow now owns Developer ID signing, notarization, Gatekeeper validation,
release assets, and the signed Sparkle appcast. A build is not considered a
public release until every one of those gates succeeds.

## Repeatable audit

The repeatable signed-package audits are
`BrowserChromeWebStoreTests.testCurrentPopularExtensionPackagesVerifyInspectAndReachExpectedRuntimeBoundary`
and
`BrowserMozillaAddonsTests.testLiveFirefoxAddonVerifiesInspectsAndLoadsWhenEnabled`.
They remain opt-in because they download current external packages and are not
deterministic enough for the ordinary unit-test gate.

Action-popup startup is covered separately by
`BrowserExtensionActionPopupLiveTests`. It drives WebKit's own
`WKWebExtensionAction.popupWebView` across ordinary and Chrome Web Store tabs,
after both a fresh install and a launch restoration, and fails when any host
call the popup depends on does not settle. These tests share the
`CREST_RUN_CHROME_STORE_INTEGRATION` gate.

Readiness assertions in these suites must treat a **missing** loader element as
not-ready. A popup document that has not parsed yet has no loader, so accepting
its absence lets the assertion pass before the popup has done anything.

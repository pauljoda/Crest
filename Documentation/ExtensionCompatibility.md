# Extension compatibility

Crest treats extension compatibility as a measured runtime result, not a
promise based only on a manifest. A package can verify, install, and load while
one of its optional or background features still reaches an API WebKit does not
implement.

The pinned platform specifications, process boundaries, and Crest routing
decision for every supported namespace live in
[`ExtensionAPICompatibilityMatrix.md`](ExtensionAPICompatibilityMatrix.md).
That matrix is the compatibility contract; individual extension behavior is
end-to-end acceptance evidence, not a source of package-specific routing.

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
- Extensions settings can also review and install a selected `.crx` or `.xpi`
  file. A CRX still has to carry both a valid developer signature and Chrome
  Web Store publisher proof. An XPI is validated as a WebExtension archive but
  remains a local package because the file alone cannot reproduce its Firefox
  Add-ons listing provenance. Both formats are copied into the selected Space,
  and neither receives store updates or verified native-companion access.
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
- **Local CRX and XPI packages** are never updated. Even when a selected CRX
  proves its Chrome Web Store signature, choosing a file does not establish the
  canonical store page needed for the update contract. A local XPI likewise
  has no trusted Firefox Add-ons listing bound to its bytes.
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
- **Saved tabs.** Crest's saved tabs are a third placement Chrome has no name
  for. They report `pinned: false`, because `pinned` means the pinned strip and
  nothing else. `tabs.update({pinned: true})` moves a saved tab into that strip,
  matching Crest's own Pin Tab action; `pinned: false` leaves it saved rather
  than pulling it out of the list.
- **New tab page override.** `chrome_url_overrides.newtab` is not honored. A new
  tab on macOS opens Crest's command palette rather than loading a page, so
  there is no URL for an extension to replace.

## Crest compatibility runtime

Crest uses WebKit as the extension engine and adds one browser-neutral runtime
above it. The runtime is selected by requested capabilities and manifest shape,
not by extension ID or vendor. It is installed into a temporary copy while the
verified store archive remains unchanged, so restoration and updates always
start from the verified bytes.

The package layer currently loads before supported Manifest V2 and V3
background forms, declared content scripts, and packaged HTML extension pages.
That last category intentionally includes internal routes reached from a popup
or options page even when the manifest does not name them directly; manifest
sandbox pages remain untouched. Manifest V3 service workers remain native
service workers: Crest points the temporary manifest at a generated bootstrap
of the same worker type, which loads the compatibility runtime before the
package's declared worker. Module workers use module imports and classic workers
use `importScripts`. Keeping that native boundary is required for WebKit to
deliver popup and content-script messages with native Port lifetime and sender
identity. A generated background document can participate in same-origin web
channels, but WebKit does not route native `runtime.connect` or
`runtime.sendMessage` traffic into it. Per-Space extension origins prevent the
service-worker registration reuse that the discarded document conversion had
worked around. The extension sees its authored manifest through
`runtime.getManifest()`.

Generated runtime and service-worker filenames include a digest of their source.
A runtime change therefore gives WebKit a new runtime URL and forces its
background content to refresh, while the context identifier and extension
storage remain stable. Without that content address, WebKit can continue
running previously prepared background content after Crest itself has been
updated.

The prepared package itself also keeps one resource-base URL for the lifetime
of the stored installation and Space. Crest prepares into a staging directory,
compares a digest of the complete result, and reuses the existing directory
when the result is unchanged. Releasing or recreating a WebKit context does not
delete that resource base. This is required because WebKit keys persistent
service workers, dynamic content scripts, permissions, and storage to the
extension resource identity; presenting the same installed package at a new
temporary URL on every launch makes it look like an update and can remove those
stores while the restored extension is starting.

The runtime preserves WebKit's native roots and `runtime` object. It copies a
missing namespace from the other native `chrome`/`browser` root where possible
and fills absent capabilities. A narrowly scoped semantic normalizer is also
allowed when WebKit exposes a method but does not honor the portable contract.
For example, `runtime.getURL` remains native-backed but is safe to retain and
call without its namespace receiver, and an empty `i18n.getMessage` lookup
returns an empty string. The runtime also supplies the standard idle-callback
scheduling contract in extension worlds that lack it and acknowledges
`webRequest.handlerBehaviorChanged()` when there is no browser-side handler
cache to flush. If an existing WebKit namespace is not augmentable, a
namespace-only facade exposes the missing members or normalized method while
returning the original native values and binding native methods to their
original receiver. Native messaging methods, events, Ports, and sender metadata
remain WebKit-owned. If WebKit supplies only one root, the missing global name
becomes an alias to that same native object. An offscreen document uses the
extension-supplied URL rather than a package-specific path.

WebKit 27's `webNavigation` surface omits the standard
`onCreatedNavigationTarget`, `onHistoryStateUpdated`,
`onReferenceFragmentUpdated`, and `onTabReplaced` events. Crest exposes
standards-shaped, presence-only event objects for those four member routes so
portable background initialization can register optional listeners without
aborting. The native `browser` and `chrome` roots remain untouched, and any
future native WebKit member wins over the fallback. Crest does not yet claim
delivery semantics for these events; Arc-level parity requires engine-backed
tab-opener, per-frame history, fragment, and tab-replacement dispatch.

The same matrix exposes the full Chromium/Firefox `privacy.network`,
`privacy.services`, and `privacy.websites` group shape. WebKit has no privacy
namespace, so Crest reports conservative platform values with
`levelOfControl: "not_controllable"`; `set` and `clear` settle without claiming
that Crest changed an engine or system preference. This lets portable packages
restore optional privacy settings without turning one missing group into a
background-startup exception.

Classic workers can also receive a lexical facade that hides WebKit's
foreground-only live-`Window` methods without replacing the native global root.
Static ES-module imports cannot inherit that lexical binding, and WebKit's
module-worker namespace rejects property-level overrides. Crest therefore keeps
the native module root so Port routing remains correct; WebKit still exposes
`extension.getViews` there even though Chrome does not. Replacing the module
root, or wrapping its runtime object, deterministically disconnects native
Ports, so this remaining engine mismatch is not papered over with a second
message router.

An earlier experimental build could save its generated worker prelude inside
an unpacked stored package. The current preparer recognizes that Crest-owned
prelude and removes it only from the temporary runtime copy. It never rewrites
the user's stored package and the migration does not inspect extension identity.

The runtime also partitions `declarativeNetRequest` `modifyHeaders` rules.
WebKit accepts only a fixed list of standard header names and rejects the whole
rule when one is missing, so the official Claude extension's session rule — which
sets `anthropic-client-platform` and `anthropic-client-version` on
`https://api.anthropic.com/*` — was refused entirely, and the Messages API then
answered its side panel with a CORS refusal. The wrapped `updateSessionRules`
and `updateDynamicRules` send WebKit the header operations it accepts and keep
the rest in a per-extension, per-Space table that every context of that
extension reads, applying them to the extension's own `fetch` and
`XMLHttpRequest` traffic. Content-script and web-page requests are outside that
boundary. See `Documentation/ExtensionEmulationServices.md` for the partition,
the broker envelopes, and what a script still may not set.

Compatibility fixes are accepted only as reusable capabilities with a fixture.
Crest does not carry extension-ID switches or literal patches to an extension's
source. Engine-owned behavior such as isolated-world creation, CSP, request
interception, and WebAuthn remains WebKit's responsibility. See
`Documentation/ExtensionEmulationServices.md` for the runtime and native broker
boundary.

### Background WebSockets on WebKit 27

On August 27, 2026, a classic Manifest V3 background worker that constructed a
WebSocket stopped its entire WebContent process. WebKit marked the process
unresponsive, and a process sample showed the worker-side WebSocket channel
synchronously waiting for work on that same process's main thread. Any popup
sharing the process could then show only its empty AppKit shell.

Deferring the construction was tried first and is not enough: the wait is on the
constructor itself, so a worker that reached it at any point still stopped the
process. A later build made every worker connection fail asynchronously, which
kept the browser alive at the cost of every extension whose background work is a
socket — a local app-server companion has nothing to fall back to.

Crest now moves the socket out of the WebContent process entirely, and handles
the capability rather than a package identity: a worker that needs a WebSocket
gets a `WebSocket`-shaped class installed over the global before the authored
worker loads, and that class carries every frame over the capability broker to a
real socket in the browser process. The native constructor is never reached from
a worker. Page contexts, and workers on a build without the defect, keep
WebKit's own implementation. The verified archive and installed bytes remain
unchanged.

The transport, its envelope, the `connect-src` enforcement that stands in for
the CSP WebKit can no longer apply, and its limits are described under *Worker
WebSocket transport* in `Documentation/ExtensionEmulationServices.md`.
`BrowserNativeMessagingTests` pins the broker half against a real WebSocket
server and `BrowserExtensionWorkerWebSocketCompatibilityScriptTests` pins the
worker half in WebKit. Live validation of the deferred-constructor build with
the signed LastPass 4.155.1 package rendered its real login popup, accepted and
submitted account credentials, reached the service's trusted-device email
challenge, retained that state after dismiss/reopen, and produced no WebKit
unresponsive-process event. The implementation contains no LastPass identifier,
name, URL, or source patch.

### Chrome package identity, storage events, and native runtime messaging

A verified Chrome Web Store package must select its Chrome code path even when
WebKit supplies the host navigator. Crest preserves WebKit's complete native
user agent and appends only the unversioned ` Chrome/` family marker. This is
enough for ordinary family detection without claiming a fabricated Chrome
feature version. The previous `Chromium/` suffix was not recognized by packages
that distinguish Chrome from Safari, which could send a Chrome package into a
Safari native-companion path and leave its background code polling at full CPU.

WebKit extension namespaces are exotic objects: inherited native methods may be
callable even when `Reflect.ownKeys` does not report them. The compatibility
facade therefore resolves an otherwise unknown native property once, caches the
result, and continues to delegate native APIs ahead of fallbacks. Manifest
permissions are also normalized after Crest adds an internal transport
permission, so one capability cannot remain in both required and optional
permission lists.

WebKit can complete and persist an extension-storage mutation without reliably
delivering the corresponding `storage.onChanged` event either to the writing
page or to another extension page. A state provider can therefore read a
missing value, subscribe for its initialization, and wait forever even though a
background worker subsequently writes the value. Crest normalizes every
available storage area, preserves the native get/set/remove/clear APIs, emits
spec-shaped root and area events in the writing page, and relays the same event
to the extension's other pages over its trusted same-origin channel. A short
signature window suppresses duplicates when WebKit also reports a mutation.

Runtime messaging stays entirely on WebKit's native path. The compatibility
facade may expose that native runtime through the `browser` spelling, but it
does not replace Chrome's root, runtime object, event objects, Ports, or sender
metadata. WebKit retains ownership of popup, background, and content-script
routing.

A verified Chrome Web Store package runs on the origin Chrome gives it:
`chrome-extension://<store id>/`, the same string in every Space, with the
extension-visible ID likewise the verified store ID. The origin is load-bearing
for anything that identifies an extension by string comparison rather than by
permission: an embedder's `frame-ancestors` list and the `ancestorOrigins`
check an embedded surface runs in JavaScript, a service's CORS exemption for
its own extension, a web-accessible-resource probe, and a redirect back to
`chrome-extension://<id>/…`. A synthetic host fails all of them silently and no
manifest or permission edit compensates. Every other source — Firefox add-ons,
local and unpacked packages, Safari web extensions — has no public origin to
preserve and keeps a per-Space host derived from
`sha256(<id>.space.<space uuid>)`.

Sharing one origin across Spaces is safe because Spaces do not share WebKit
storage. Every Space owns a `BrowsingProfile` — `BrowserSession.makeBlankSpace`
mints a fresh one and `repairRuntimeIntegrity` reidentifies any duplicate — and
each Space's extension controller is built on
`WKWebsiteDataStore(forIdentifier: profile.id)`. Service-worker registrations,
the reason this host was ever hashed, live inside that per-Space store, so one
Space cannot reuse another Space's dormant registration and lose its runtime
listeners. `BrowserExtensionRuntimeContextController` still checks that
invariant against live state on every load rather than trusting it: if a
different Space with the same `profile.id` already runs the package, the second
Space falls back to the hashed per-Space host and the fallback is written to
the `extension-diagnostics` log.

`BrowserExtensionControllerPoolTests.testModuleWorkerUsesWebKitsContentTabIdentity`
and `testClassicWebSocketWorkerUsesWebKitsContentTabIdentity` pin one-shot and
Port delivery plus native tab, frame, and document sender identity. Live
validation with Bitwarden 2026.8.0 confirmed that the corrected Chrome path
remained idle after its animated onboarding tab closed, its welcome and login
popups rendered, and its region changed immediately in the writing popup. A
fresh first login then completed authentication, received background state
initialization in the already-open popup, moved
directly from `/login` to `/tabs/vault` without a restart, and remained
interactive on the Generator route. Before the cross-page storage event was
restored, the same write reached WebKit's storage database but the popup's route
guard remained subscribed to the old missing value; reopening Crest only hid
that race by reading the persisted value at startup.

`BrowserChromeWebStoreTests.testCompatibilityLayerDispatchesStorageChangesInTheWritingPage`
pins callback and Promise mutations, root and area listeners, change values,
and removal/clear behavior when the native writing page reports no event.
`BrowserChromeWebStoreTests.testCompatibilityLayerBridgesStorageChangesAcrossExtensionPages`
pins delivery to an already-open extension page, including a stored `false`
value of the kind that exposed the first-login deadlock.

### Externally connectable web pages

Chrome lets a website named in an extension's `externally_connectable.matches`
call `chrome.runtime.sendMessage(extensionID, message)` and
`chrome.runtime.connect(extensionID)`, and the extension answers through
`runtime.onMessageExternal` / `runtime.onConnectExternal`. WebKit implements
the same round trip — it parses the manifest key, installs a web-page
namespace with exactly those two members, checks the patterns and the
extension's host permission when the page sends, and reports the page's
`origin`, `url` and `tab` in the sender — but it installs that namespace under
`browser` only. Its `addBindingsToWebPageFrameIfNecessary` never sets `chrome`,
so a page written for a Chrome Web Store package finds `chrome` undefined and
gives up. Claude's sign-in is the concrete case: after claude.ai authorizes the
extension it hands the OAuth code back with
`chrome.runtime.sendMessage("fcoe…", { type: "oauth_redirect", redirect_uri })`
and shows "Authorization failed" when nothing answers.

Crest closes the gap with `BrowserExtensionWebPageRuntimeBridge`, a
document-start user script in the page world of every web page Crest
configures itself. It receives the union of the Space's authored
`externally_connectable.matches` patterns
(`BrowserExtensionControllerPool.externallyConnectableMatchPatterns(in:)`,
read by `BrowserExtensionExternallyConnectablePolicy`) and, on a frame whose URL
matches one of them while WebKit's `browser.runtime` is present, defines
`chrome.runtime` with `sendMessage` and `connect` forwarding to WebKit's object.
That is the exact footprint Chrome exposes there. Rules:

- Frames that match no pattern keep `chrome` undefined, so ordinary websites
  never mistake Crest for Chrome. Extension pages already carry `chrome`, a
  popup runs its opener's scripts, and private Spaces load no extensions, so
  none of them receive the script.
- The pattern set is fixed when the page is created. A page that was already
  open when an extension was installed gains the alias on its next load.
- WebKit's web-page `sendMessage` answers an unknown extension id, an
  unmatched page, or a listener that never responds with a plain `undefined`.
  Chrome reports all of those through `chrome.runtime.lastError`, set only
  while the callback runs, or by rejecting the promise form. The alias
  reproduces that: an `undefined` reply sets `lastError` to "Could not
  establish connection. Receiving end does not exist." for the duration of the
  callback and rejects the promise with the same message. Pages depend on it:
  claude.ai's authorize screen probes Anthropic's internal extension id before
  the public one and treats an error-free `undefined` as a completed hand-off,
  so without the signal the sign-in never reaches the installed extension.
- Under extension console capture, every web-page call into an extension and
  its outcome (replied, unanswered, rejected, threw, with elapsed time) is
  written to the `extension-diagnostics` log as shapes only — a type field and
  key names, never payload values.

### Extension-created popup windows

WebKit's `windows.create({ type: "popup" })` result is context-dependent. An
extension page can reach Crest's window delegate, while the same call from a
toolbar action popup can settle with a window-shaped value without presenting
a host window or invoking the delegate. Accepting that value leaves the
extension believing its popout opened even though no window exists.

Crest therefore owns the browser-generic single-URL popup case. The compatibility
runtime sends the unchanged create data to Crest's capability broker, which
presents the page through the normal auxiliary-window coordinator. The runtime
then asks WebKit for the published popup and returns WebKit's real window and
tab identifiers; it never fabricates an ID. Focus, update, removal, and close
events consequently use the same objects as every other extension window.
Multi-tab and non-popup window requests stay on WebKit's native path.

The foreground extension page contacts that host-owned broker directly. It
does not relay through an MV3 service worker: a broadcast channel cannot wake a
suspended worker, and a toolbar popover can disappear while a relayed request
is still pending. Native authorization remains scoped to the installed
extension and reviewed permissions, exactly as it is for a background worker.

`BrowserChromeWebStoreTests.testCompatibilityWindowsCreateUsesCapabilityBrokerForSingleURLPopupAndReturnsNativeWindow`
pins the page contract, and
`BrowserExtensionControllerPoolTests.testCapabilityBrokerPresentsARejectedPopupAsANativeExtensionWindow`
pins native presentation and controller ownership.

### Cookies for sites an extension frames

Claude's side panel offers a "Cowork" mode that frames
`https://claude.ai/cic/new?surface=cic_sidepanel` inside the extension page.
The frame loads, and claude.ai inside it reports that nobody is signed in.

The cause is engine-side. WebKit already relaxes third-party cookie *blocking*
for extension web views, but `SameSite` is a separate decision made in WebCore
from the registrable domain of the **top** document, and it has no extension
exemption. Under a `chrome-extension://` top document a `claude.ai` frame is
cross-site, so every cookie the site marked `SameSite=Lax` or `Strict` is
withheld — not only from the frame's own navigation but from every request that
frame's document makes afterwards, because its site-for-cookies stays the top
document. Chrome does not have this problem: an extension page holding host
permission for a site is treated as first-party for that site's cookies.

Crest adopts the same rule, and pays for it in the one currency it owns. When
one of an extension's own pages frames a site the extension has host permission
for, Crest rewrites that site's cookies **in that Space's website data store**
to drop the `SameSite` attribute. Name, value, domain, path, expiry, `Secure`,
`HttpOnly`, and port are all preserved; only `SameSite` is removed. WebKit does
not apply Chromium's Lax-by-default, so a cookie carrying no `SameSite`
attribute is simply sent, which is why removing the attribute is enough and
nothing has to claim `SameSite=None`.

The scope is deliberately narrow:

- **That Space only.** The jar is resolved from the Space's own extension
  controller — the same `WKWebsiteDataStore` its extension web views were
  configured with — never rebuilt from the profile. Other Spaces are untouched.
- **Only hosts the extension has permission for.** The check is
  `WKWebExtensionContext.hasAccessToURL:` against the granted match patterns,
  which is the grant the user made at install.
- **Only after one of its pages frames the site.** The trigger is a subframe
  navigation to an `http(s)` URL from a Crest-owned extension document. A
  main-frame load of the extension page itself, a non-web frame, and a host
  with no permission all rewrite nothing.
- **Enforcement lasts as long as the extension is loaded in that Space.** A
  login response re-sets the same cookies as `Lax`, so a cookie-store observer
  re-applies the rewrite. It is removed once no client in the Space still lists
  the host.
- **Nothing is persisted.** A fresh launch relaxes nothing until a frame loads
  again. Cookies already rewritten stay rewritten — Crest does not invent a
  `SameSite` value the site never sent — but the re-application stops.

The trade-off is real and the user accepts it at install: within that Space,
those cookies no longer carry the cross-site request protection `SameSite` gave
them, so any cross-site request in that Space that reaches the host will send
them. It is bounded by the Space, by the host permission the user granted, and
by the extension staying loaded, but it is not free. Extensions already have
full access within their Space, which is what makes the bound the meaningful
one.

Crest owns the navigation delegate for the side panel document and the
offscreen document, and both apply the rule. It does **not** own the action
popup's web view: WebKit creates `WKWebExtensionAction.popupWebView` and is its
own navigation delegate, so there is no Crest seam there and a site framed by a
popup is still subject to WebCore's decision.

`BrowserExtensionCookieAccessPolicyTests`,
`BrowserExtensionCookieAccessStoreTests`,
`BrowserExtensionCookieJarCoordinatorTests`, and
`BrowserExtensionFramedSiteCookieAccessTests` pin the rewrite, the per-Space
bookkeeping, the live `WKHTTPCookieStore` behavior including the observer, and
the permission gate.

## Native companion distribution boundary

- Ordinary WebExtensions can use APIs implemented by WebKit.
- Crest for Mac supports native messaging for verified Chrome Web Store and
  Firefox Add-ons installations. It discovers each browser format's registered
  host directories and validates the exact verified identity: Chrome
  `allowed_origins` entries use `chrome-extension://<id>/`, while Firefox
  `allowed_extensions` entries use the Gecko ID. Host launch arguments also
  follow the corresponding published protocol. Both formats then use the same
  little-endian framed JSON transport for one-shot `sendNativeMessage` calls
  and persistent `connectNative` ports.
- WebKit can deliver a native-message request without an application identifier
  when the extension intentionally passes an empty string. Crest handles that
  portable form without guessing: it enumerates registered `<name>.json`
  manifests in browser search order, requires the filename and internal name to
  agree, filters them by the verified extension identity, and proceeds only
  when exactly one host remains. Zero matches or an ambiguous result fail
  closed. Crest never selects a companion from its executable name, bundle
  identifier, extension name, or vendor.
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
  the shared compatibility overlay, background load, verified native
  messaging, and removal are covered.
- **Unpacked WebExtension:** manifest inspection, permission review, isolated
  per-Space installation, runtime loading, and removal are covered. Native
  messaging remains unavailable to this path.
- **Signed Safari Web Extension app:** Crest can discover and load an ordinary
  WebExtension component through **Scan for Apps** or **Choose App**. This does
  not make a third-party Safari native handler portable.
- **Crest for Mac native messaging:** regression coverage includes a real child
  native-host process exchanging framed JSON, exact Chrome and Firefox manifest
  identity checks, and real `WKWebExtension` backgrounds reaching Crest's
  delegate with their source-appropriate verified identity.

## Primary compatibility gates

Crest uses two deliberately demanding extensions as release-quality validation
targets. Passing means their real user workflows work in a Developer ID-signed
build; merely loading the package or hiding its diagnostics is not a pass.

- **uBlock Origin 1.73.0 from Firefox Add-ons** is the Manifest V2 gate. Its
  background page must finish startup, the popup must show live page statistics,
  and popup-to-background Ports must work. Network and cosmetic blocking, the
  per-site power control, logger, dashboard, filter-list updates, settings
  persistence, and restart restoration must all be exercised.
- **1Password 8.12.32.33 from the Chrome Web Store** is the Manifest V3 and
  native-companion gate. Its worker must initialize, connect to the trusted
  1Password desktop app, render an unlocked popup, search accounts, fill and
  save a real field, and preserve that connection across a Crest restart.
  Extension passkey interception is part of this gate once the corresponding
  browser and website WebAuthn path is available.

Every defect discovered by these gates must become a capability-based fixture.
Neither extension ID, package name, nor a literal patch to vendor source is an
acceptable compatibility mechanism.

### Completion map

| Gate | Current evidence | Remaining proof or implementation |
| --- | --- | --- |
| 1Password package and background | Chrome 8.12.32.33 and Firefox 8.12.32.33 both verify, install, and complete an isolated startup audit without a manifest, runtime, or unsupported-API error; Chrome uses an MV3 worker and Firefox uses an MV2 background page | Keep both packages in the audit; prefer Chrome while its CRX3 provenance and automatic update path remain stronger |
| 1Password native companion | The Developer ID app launches the registered helper as Crest's child with the verified Chrome origin; framed one-shot and persistent transports have focused fixtures | Finish 1Password's explicit trust authorization, then prove unlocked account discovery and a persistent Port |
| 1Password popup and page integration | The popup no longer stops on the earlier missing managed-storage, manifest, or navigation members; content scripts are injected at document start | Render a real unlocked popup, search an account, fill and save fields, close/reopen the popup, and repeat after restarting Crest |
| 1Password passkeys | The package's main-world WebAuthn listeners load and no longer fail at the earlier missing preference surface | Prove create/get interception, user cancellation, system-passkey fallback, and a real saved passkey after the desktop connection is trusted; separately retest native website passkeys when Apple grants Crest's managed browser entitlement |
| uBlock MV2 runtime and UI | Firefox 1.73.0 background page starts, popup-to-background communication works, and the popup displays live statistics and controls | Exercise dashboard, logger, settings, filter updates, restoration, and cosmetic filtering after the blocking boundary exists |
| uBlock request enforcement | WebKit exposes the permission and some observation events; the test page shows partial blocking only | Implement an enforceable native request/response interceptor and policy cache, or maintain a reviewed WebKit fork; a JavaScript shim or detached helper alone cannot complete this gate |

The 1Password path does not need a Crest interpreter process. Its official
`1Password-BrowserSupport` executable is already the correct background
process. A future uBlock policy evaluator could run out of process for isolation
and compilation cost, but the browser process would still need a synchronous,
permission-aware hook into WebKit's request lifecycle.

## 1Password live validation

The signed Chrome Web Store package for 1Password 8.12.32.33 now reaches the
native-companion boundary without an extension-specific patch. In a fresh
Manifest V3 worker inspection on August 16, 2026, it initialized persistent and
session storage, loaded its WASM and XAM components, finished background
initialization, and sent its account request through Crest's native-messaging
port. The earlier missing `storage.managed`, `runtime.getManifest()`, passkey,
and `webNavigation.onCreatedNavigationTarget` members no longer stop startup.

In the Developer ID build installed at `/Applications/Crest.app`, that request
launches 1Password's registered `1Password-BrowserSupport` executable as a
direct child of Crest with the exact allowlisted
`chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/` origin. Re-adding the
current signed app through 1Password's **Add Browser** flow opens a chooser that
recognizes `/Applications/Crest.app`, but Crest has not yet been added to
1Password's trusted additional browsers. Account discovery, popup unlock, field
fill, and restart restoration therefore remain pending. Selecting the app is a
security-sensitive, persistent grant to the unlocked vault and must be approved
explicitly by the person using the Mac.

1Password then deliberately rejected the unsigned development copy with
`BrowserVerificationFailed` / `UnknownBrowser`. This is not a WebExtension API
gap. On macOS, 1Password authenticates the browser's code signature and allows
an unsupported browser only after the person explicitly trusts it. The
supported path is:

1. Install the Developer ID-signed Crest build at `/Applications/Crest.app`.
2. Open and unlock 1Password.
3. Choose **Settings → Browser → Add Browser** and select Crest.
4. Restart Crest and confirm the popup, account discovery, and a real field
   fill.

Crest must not masquerade as Chrome, weaken that verification, or auto-edit
1Password's trust list. A debug build outside Applications is expected to fail
this handshake. Website passkey registration is also a separate boundary:
WebKit rejects it until Crest's signed build carries Apple's managed browser
public-key-credential entitlement.

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
installs. Crest's capability-selected runtime supplies optional WebKit APIs the
package expects but WebKit does not expose:

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

Removing the rewrite keeps the stored package byte-identical to the verified
store payload. If Dark Reader requests a capability in the shared overlay,
Crest prepares the same temporary, capability-selected runtime copy used for
every other extension; it does not edit Dark Reader's source or retain that
copy as the installed package.

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

### Messaging stays split at the engine-owned content-script boundary

Popup warm-up remains useful because Crest directly controls popup creation.
It is not the compatibility transport for ordinary extension messages.

All extension-page and content-script `runtime.sendMessage`, `runtime.connect`,
and `tabs.sendMessage` traffic stays on WebKit's native path so WebKit retains
callback and Promise replies, Port lifetime, and sender tab/frame/document
identity. Replacing a native root or recursively rewriting its event objects
prevents WebKit from delivering those events, so the compatibility layer keeps
the Chrome runtime object and event identity intact.

This is capability mapping rather than a patch to Dark Reader, 1Password, or
any other extension. It also avoids maintaining a second message router whose
targeting and lifecycle could drift from Chrome, Firefox, and WebKit.

### A content script cannot be answered for a page extensions were never told about

WebKit answers a content script's `runtime` messages only for a web view it can
map onto a tab the host has announced. For an unannounced page it rejects the
message outright — `Tab not found for message for content script message`,
surfacing to the extension as `Invalid call to runtime.sendMessage(). Tab not
found.` and recorded as `WKWebExtensionContextErrorDomain Code=7`. Nothing
retries it, so an extension that asks its background for configuration at
document start keeps whatever partial state it applied while asking, for the
life of that document. Reloading the page fixes it permanently, because the
second injection happens after the announcement.

This is not the stopped-worker defect. Measured in an ordinary session on
August 15, 2026, the failure occurred with the extension's background page alive
and its worker running, and no background page was constructed at all in
response — the message never reached the background to wake it:

```
17:22:43.423  pageProxyID=7505  WebPageProxy::constructor
17:22:43.427  pageProxyID=7505  WebPageProxy::loadRequest:          ← +4ms
17:22:43.586  pageProxyID=7505  WebPageProxy::didCommitLoadForFrame
17:22:43.653  [WebKit:Extensions] Tab not found for message for content script message
17:22:43.848  [WebKit:Extensions] Invalid call to runtime.sendMessage(). Tab not found.
```

Three pages in one session showed it, each constructed and navigated within
4–7 milliseconds. Each one that was later reloaded produced no second error:

```
16:17:45.373 constructor → 16:17:45.378 loadRequest → 16:17:46.104 Tab not found
16:17:49.301 reload:      → 16:17:49.892 commit     → (no error)
```

Two Crest paths built a web view and navigated it before that web view was
anything extensions had been told about:

- **A Peek.** `BrowserPagePool.makeTransientPageLease` builds a page with the
  Space's extension controller attached, and `BrowserTransientPageLease`'s
  initializer navigates it. The lease never enters the session, and the tab
  coordinator's whole model is session-derived, so the page was never announced
  at all — not late, never. A Peek promoted into a tab or a split card carries
  its already-broken document across, which is how the same symptom reached
  Split View.
- **The cards a selection presents.** `BrowserPagePool.select(session:)` started
  every presented card's initial navigation before reconciling extension state,
  so the announcement trailed the load that injects content scripts.

Both now announce first. Selection builds its cards, announces them, then
navigates them; a Peek's page is registered as a transient tab and announced
before the lease's first load, and the announcement is withdrawn when the lease
is released, evicted under memory pressure, or handed to a real tab that
announces itself.

Announcing a Peek is the truthful description rather than a convenient one. The
page is a live document in that Space with the extension's content scripts
already running inside it; hiding it from `tabs` while executing extension code
in it was the dishonest half of the previous arrangement, not the disclosure. It
is announced as an ordinary unselected tab and never as the active one, so
"a Peek is never the active page" still holds.

`BrowserExtensionTransientTabAnnouncementTests` pins both orders, and fails
against the previous ones: the Peek page is never announced, and a split
member is announced only after its web view is already loading.

The page-announcement ordering above is required for every native message form:
WebKit must know which tab owns the content script before it can deliver a
one-shot message or establish a Port. A real-controller fixture now verifies
content-to-background `runtime.sendMessage`, direct Port sender metadata,
`tabs.query`, and background-to-content `tabs.sendMessage` together.

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

The following signed Chrome Web Store packages were audited on August 16, 2026.
Each package verified, installed into an isolated Space, and loaded. "Loads
cleanly" means no startup error was observed; it does not certify every account,
site, popup, update, or optional workflow.

| Extension | Version tested | Initial result | Measured boundary |
| --- | --- | --- | --- |
| Dark Reader | 4.9.129 | Loads cleanly | Installs unmodified; live page attachment and popup reopen verified separately |
| uBlock Origin Lite | 2026.812.1211 | Loads cleanly | Declarative Net Request package loaded without a startup error |
| 1Password | 8.12.32.33 | Worker clean / signed-browser authorization pending | The generic MV3 worker reaches 1Password's native core and sends its account request. An unsigned development copy is rejected as `UnknownBrowser`; the installed Developer ID build must be added through 1Password's supported **Add Browser** flow before popup and field-fill certification |
| SponsorBlock | 6.1.6 | Loads cleanly | No manifest or startup runtime error observed |
| Bitwarden | 2026.8.0 | Login, vault, popout, and autofill verified | The signed Chrome package completed fresh device verification and login, opened its vault, unlocked again after a real Crest relaunch, presented a native auxiliary popout, exposed its in-page menu, and filled the selected test credential on fill.dev. CPU returned to idle after synchronization |
| LastPass | 4.155.1 | Login, vault, relaunch, and autofill verified | The signed Chrome package accepted the account login, reopened signed in after a real Crest relaunch, listed its matching fill.dev item in the action popup, injected its in-field integration, and filled both credential fields at idle CPU |
| Grammarly | 14.1320.0 | Partial / experimental | The worker loads; account-cookie access and an initial tab-creation request still report runtime failures |
| React Developer Tools | 7.0.1 | Partial / experimental | `chrome.scripting.ExecutionWorld.ISOLATED` is unavailable |
| Tampermonkey | 5.5.0 | Partial / experimental | WebKit rejects its `tabs.onUpdated` startup registration. Crest now reports loading and reader-mode changes to that event, but the rejected registration is a WebKit boundary and is unchanged |
| iCloud Passwords | 3.3.0 | Blocked / Apple entitlement pending | The worker loads through the generic capability runtime, but Apple's password helper rejects the current unsigned-capability parent; pairing and autofill require the managed browser credential entitlement |

## Firefox extensions from addons.mozilla.org

Firefox is in several respects a better native fit for WebKit than Chrome.
`WKWebExtension` accepts Manifest V2 with a persistent background page, and the
promise-based `browser.*` namespace Firefox extensions are written against is
what WebKit implements natively. Firefox packages still enter the same
capability-selected overlay as Chrome packages when WebKit omits a requested
standard API. Crest does not maintain a second Firefox shim or select behavior
from a vendor or extension ID.

### Choosing a Chrome or Firefox package

Crest should not declare either store universally primary. Source is a product
of package shape, required APIs, provenance, and update support:

- Prefer a Firefox package when its maintained Manifest V2 background document
  materially avoids a Manifest V3 service-worker lifecycle problem, or when it
  is the only maintained full-featured package, as with uBlock Origin.
- Prefer a Chrome package when its CRX3 signature and Crest's automatic update
  path are more important and the extension's Manifest V3 worker is already
  proven in WebKit.
- Present both when both are available and record compatibility by exact source
  and version. A pass for one package is not evidence that the other passes.

The current 1Password 8.12.32.33 packages contain the same application code and
use the same WebExtension APIs. The Firefox package changes the host shape to a
Manifest V2 `background.page` and adds `webRequestBlocking`; it still needs
native messaging, page injection, WebAuthn interception, notifications, tabs,
and navigation. 1Password installs matching native-host manifests for both the
Chrome ID and Firefox Gecko ID. In the August 16 isolated audits, both packages
started without a manifest, runtime, or unsupported-API error. Firefox is
therefore a useful secondary lifecycle gate, not a demonstrated compatibility
advantage for 1Password and not a substitute for the person's explicit browser
authorization.

Firefox cannot become Crest's default acquisition path until the remaining
provenance and update gaps are closed. Crest currently verifies the AMO API's
TLS-delivered digest, size, identity, and presence of Mozilla signing material,
but does not yet cryptographically validate the complete signed XPI entry graph
and does not automatically update Firefox installations.

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

Firefox add-ons receive a Space-namespaced WebKit runtime identifier
(`<gecko-id>.space.<space-uuid>`), like every non-Chrome source. Native host
authorization does not reuse that internal identifier. Crest carries the
verified store identity separately and checks it against the host manifest:
Chrome uses `allowed_origins`, while Firefox uses `allowed_extensions`.

The separation is intentional. Space isolation remains part of WebKit storage
and extension origins, while a companion app sees exactly the store identity it
registered. Unpacked packages still cannot use native messaging because they
do not have a verified store identity.

### Expected gaps

WebKit reports Firefox-only manifest keys as errors and warnings rather than
refusing the package. Those surface in the review sheet's **WebKit Compatibility
Warnings** section and are recorded with the installation; they do not block
installation. Expect the following to be unavailable:

- `contextualIdentities` container tabs
- `theme` and dynamic theme APIs
- Blocking `webRequest` request cancellation and modification
- `browserSettings`
- `menus` beyond what WebKit's `contextMenus` implements

On macOS, `sidebar_action` is emulated by Crest's trailing split-row panel,
including title/panel overrides, path icons, the reserved sidebar command,
and first-install opening. Image-data icons reject explicitly. WebKit's
manifest warning does not describe Crest's host implementation.

### Firefox package audit

The following listings were acquired, verified, installed into an isolated
Space, and loaded on August 16, 2026 by
`BrowserMozillaAddonsTests.testLiveFirefoxAddonVerifiesInspectsAndLoadsWhenEnabled`.
"Loads cleanly" means no startup error was observed; it does not certify every
account, site, popup, update, or optional workflow.

| Extension | Version tested | Initial result | Measured boundary |
| --- | --- | --- | --- |
| Dark Reader | 4.9.129 | Loads cleanly | No manifest or runtime error observed, and no unsupported API reported |
| uBlock Origin | 1.73.0 | Partial / experimental | The shared runtime gets the MV2 background page and popup running with live page statistics and working controls. Crest also repairs WebKit's child-document request classification: a document carrying a non-root `parentFrameId` is exposed as `sub_frame` instead of `main_frame`, preventing an iframe policy decision from being mistaken for a whole-tab navigation. In the August 30 live run with Crest's built-in blocker disabled, the test site stayed in the tab, completed at 48/100, and uBlock reported 14 blocked decisions with 0 of 8 domains connected; the same page in Arc completed at 39/100. Full cancellation, redirect, header modification, and authentication response parity remain unavailable because WebKit does not consume blocking `webRequest` responses |
| Bitwarden | 2026.7.0 | Partial / experimental | The signed package and core worker load, and Crest supplies the missing notification lifecycle and click events through its verified capability broker. The Firefox build does not request `nativeMessaging`; account unlock/autofill remains uncertified |
| 1Password | 8.12.32.33 | Background clean / signed-browser authorization pending | The MV2 background page loads without a manifest, runtime, or unsupported-API error. Its Firefox native-host registration matches the package's Gecko ID; the same explicit 1Password browser trust and real popup, fill, save, restart, and passkey validation remain required |

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

A named isolated profile — `CREST_ISOLATED_SESSION=1` together with
`CREST_ISOLATED_PERSISTENCE_ID=<name>` — keeps its installed extensions across
relaunches, so a repeated audit does not begin by re-adding every extension
under test. That profile stages its packages under
`~/Library/Application Support/Crest/Isolated/<name>/Extensions` and records
the installations in the `<bundle id>.isolated.<name>` preferences domain,
which is the same boundary its browser session and WebKit storage already use
and is never the installed app's own state.

Readiness assertions in these suites must treat a **missing** loader element as
not-ready. A popup document that has not parsed yet has no loader, so accepting
its absence lets the assertion pass before the popup has done anything.

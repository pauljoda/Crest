# Extension compatibility runtime and services

WebKit remains Crest's extension engine. It owns package loading, isolated
worlds, content-script timing, permissions, extension origins, CSP, service
workers, Declarative Net Request, and the APIs it already implements. Crest
does not duplicate or replace those security-sensitive engine contracts.

Crest adds a browser-neutral compatibility runtime above that substrate. Its
only job is to fill a missing standard surface or normalize a semantic mismatch
that Crest can implement honestly. Native WebKit objects and engine behavior
remain authoritative. A native method is wrapped only when its exposed calling
contract differs from the shared WebExtension contract, and the wrapper still
delegates to that native method before using a bounded fallback.

## Architecture contract

1. **WebKit substrate.** `WKWebExtension` and `WKWebExtensionController` keep
   ownership of extension execution and document integration.
2. **JavaScript compatibility runtime.** A generated, versioned runtime is
   loaded before prepared background content, declared content scripts, and
   packaged extension pages. It normalizes the `chrome` and `browser` roots,
   preserves the declared manifest, and provides bounded local adapters where
   no native round trip is needed.
3. **Crest capability broker.** APIs that need application state call one
   permission-checked broker. The broker resolves the extension and Space from
   the loaded context; JavaScript never supplies or overrides that identity.
4. **App-side services.** Behavior that needs the app rather than the engine
   lives behind framework-neutral ports. They do not import WebKit or know how
   a package was acquired. Notifications is the one service built this way
   today; the rest of the broker's surface is served in place.

Package preparation is selected from manifest shape and requested
capabilities, never an extension ID, name, vendor, or hard-coded resource path.
The verified store archive remains untouched. Crest creates a temporary runtime
copy on each load and discards it with the WebKit context, so updates and
restoration always begin from the verified bytes.

For unpacked packages saved by an earlier experimental build, the temporary
preparer also removes Crest's legacy generated worker prelude from the runtime
copy. The stored package is not rewritten, and the migration recognizes Crest's
own code shape rather than an extension identity.

The runtime must not silently claim an engine capability Crest cannot enforce.
A missing API gets one of three outcomes:

- a native WebKit implementation;
- a Crest implementation with the same permission and Space boundaries; or
- an explicit unsupported rejection or diagnostic.

No extension-specific patch is an accepted fourth outcome. A compatibility
failure becomes a small fixture in the conformance corpus and either produces a
general capability or remains documented as unsupported.

## Current package layer

The package layer covers verified Chrome Web Store and Firefox Add-ons
resources that request a capability known to need normalization. Both formats
enter the same preparer after their store-specific acquisition and provenance
checks. It supports:

- Manifest V3 module workers through a generated module-worker bootstrap that
  statically imports the compatibility runtime before the declared module;
- classic service workers through a generated classic-worker bootstrap that
  imports the compatibility runtime before the declared worker;
- Manifest V2 `background.scripts` by inserting the runtime first;
- declared isolated content scripts and every packaged HTML extension page. This
  includes internal routes reached from a popup or options page even when the
  manifest does not name them directly. Manifest sandbox pages are excluded,
  because injecting privileged extension APIs there would violate the sandbox;
- native-first `chrome`/`browser` capability augmentation, namespace-only
  facades for WebKit objects that cannot be extended in place, an exact
  `runtime.getManifest()` fallback, managed-storage empty-policy semantics,
  receiver-safe `runtime.getURL`, empty-message i18n semantics even for a
  non-augmentable native namespace, idle-callback scheduling, optional
  navigation events, `webRequest.handlerBehaviorChanged()` acknowledgement,
  and the broker-backed `idle`, `notifications`, `contextMenus`, `offscreen`, `sidePanel`, `sidebarAction`,
  and `downloads.download` APIs. The offscreen document is hosted by Crest at
  the URL supplied by the extension.

For a Manifest V3 package that enters this layer, the temporary host manifest
stays Manifest V3. Only its `background.service_worker` path is redirected to a
bootstrap with the same classic-or-module shape. Generated filenames are
content-addressed, so a runtime change forces WebKit to refresh the worker
registration without changing the extension's context identity or storage.
Only the temporary copy is prepared; verified store bytes are never rewritten.

Content scripts declared with `world: "MAIN"` remain unchanged. They share the
website's globals, so installing the extension runtime there would overwrite
the page's externally-connectable messaging API with an unrelated extension's
identity. Omitted `world` and explicit `ISOLATED` declarations retain the
compatibility prelude.

This is the reusable JavaScript/package foundation, not full Chrome parity.
The capability broker currently connects notifications, system idle state,
context menus and the install lifecycle, Crest-hosted offscreen documents and
side panels, and `downloads.download`. Notifications and side panels are
port-backed app-side services; the rest are answered where the state already lives.
Every request is authorized from the verified loaded context, and persistent
event ports select one permission-checked capability after connection. Until
another app-side service is connected, its local adapter must stay bounded or
explicitly reject.

Chrome and Firefox packages intentionally remain distinct acquisition formats,
not distinct compatibility runtimes. Chrome commonly supplies Manifest V3
module workers and identifies native hosts through `allowed_origins`; Firefox
can retain Manifest V2 background pages and identifies native hosts through
`allowed_extensions`. Once those declared format differences are normalized,
the runtime selects behavior from API presence and execution context only.

## Cross-context messaging

WebKit owns cross-context messaging without a Crest relay. The compatibility
runtime never replaces or wraps native `runtime`, `tabs`, `onMessage`,
`onConnect`, `sendMessage`, or Port objects. That keeps callback and Promise
behavior, Port lifetime, and sender tab/frame/document identity inside the
engine that created the isolated content world.

The generated runtime captures WebKit's existing `chrome` and `browser` roots.
It copies an absent top-level native namespace from the other root, fills only
missing capability members, and defines the missing root name as an alias only
when WebKit supplied a single root. When WebKit exposes a non-augmentable
namespace, Crest overlays that namespace alone: original members and events are
returned unchanged, and original methods are bound to the native namespace.
The roots, `runtime`, and messaging objects keep their native identity.
`runtime.getManifest()` is the deliberate exception: it returns the extension's
authored manifest rather than Crest's temporary worker redirection.

The scoped worker view hides foreground-only runtime methods. Its
`runtime.lastError` getter remains live: errors belong to a callback, not to
the namespace's cached capability surface. For emulated callback failures,
the runtime first verifies that an error property can actually be read back.
WebKit's native runtime can reject or ignore that override. In that case the
verified internal `runtime.callbackError` broker request returns the failure
through WebKit itself, and the package callback runs while WebKit publishes
`lastError`. This request performs no browser action and accepts only a bounded
error message from an authorized extension context. Promise failures keep
their existing rejection path.

The host still has one required responsibility: every live web view that can
run extension content must be announced to `WKWebExtensionController` before
navigation begins. Otherwise WebKit cannot associate the isolated-world sender
with a tab and rejects the extension's own message as “Tab not found.” The
native integration fixture covers content-to-background `runtime.sendMessage`,
`runtime.connect` sender metadata, `tabs.query`, and background-to-content
`tabs.sendMessage` in one round trip.

No extension source is inspected or patched, and no extension-specific
transport exists.

## Native companion broker

WebKit owns the extension-side `runtime.sendNativeMessage()` and
`runtime.connectNative()` objects. Crest implements the app delegate boundary
by launching an already registered Chrome or Firefox native host and relaying
their standard length-prefixed JSON protocol. This child process is the
extension vendor's companion, not a Crest JavaScript interpreter and not an
alternate extension engine.

Host resolution is bound to the installation's verified store identity.
Chrome manifests must contain the exact `chrome-extension://<id>/` origin and
receive that origin as their first launch argument. Firefox manifests must
contain the exact Gecko ID and receive the manifest path plus Gecko ID defined
by Firefox's protocol. Unpacked packages never enter this broker.

Some portable extensions call the native APIs with an empty application name,
and WebKit then supplies no application identifier to its delegate. Crest may
infer a host only from registered manifests in the corresponding browser's
search order. Each candidate must be stored as `<name>.json`, declare the same
name, explicitly allow the verified identity, and name an executable absolute
path. A lower-priority duplicate does not bypass a higher-priority
registration. Exactly one distinct authorized host must remain; otherwise the
request is rejected. There is no vendor list or extension-specific fallback.

Two different capabilities travel over the same WebKit delegate. Launching an
external host is the one App Sandbox forbids, and a sandboxed build reports it
as unavailable. Requests addressed to Crest's own broker identifier are not
that: they are the in-process emulation transport for notifications, idle,
the contextMenus relay, and the `runtime.onInstalled` acknowledgement, and they
spawn no process at all. The broker is therefore answered before the
external-host capability is consulted and stays available in every build,
including the sandboxed App Store one.

This boundary is sufficient for 1Password's official `1Password-BrowserSupport`
process. It is not sufficient for uBlock Origin because uBlock's missing
contract is synchronous request cancellation and mutation inside the browser,
not a background computation process.

## Extension diagnostics

WebKit records only what an extension's API callbacks throw, so an uncaught
exception or an unhandled promise rejection in a popup, an extension page, or a
background worker reaches nobody — which is why a Bitwarden popup could go
blank after a two-factor sign-in leaving nothing to read. Chrome keeps those on
the extension's own error page; Crest's equivalent is a diagnostics channel in
the generated runtime. In privileged extension contexts only — never a content
script, whose origin is the page's — it installs `error` and
`unhandledrejection` listeners plus a report for the runtime's own "Unchecked
runtime.lastError" console line, and sends each as a `diagnostics.report`
message over the same in-process capability broker. The broker answers it for
any authorized broker context with no permission grant at all, because the
payload is the extension's own error text rather than a capability: each report
is logged under subsystem `com.pauldavis.crest`, category
`extension-diagnostics`, with the source URL trimmed to its path so a query
string or fragment an extension page carries is never logged, and the uncaught
errors and rejections are also appended to a bounded in-memory ring (20 per
context, newest wins) that the extension's runtime summary merges into the
errors shown under *Needs attention → Technical Details*. A build may also
enable console capture (`CREST_EXTENSION_CONSOLE_CAPTURE=1`, and always in an
isolated launch), which forwards the extension's own `console.warn`/`error`/
`info` calls as `kind: "console"` reports logged at `.info` and never added to
those errors — the only trace a *hang* leaves, since nothing throws. The
channel is strictly one-way telemetry and must never change what an extension
observes: a missing transport is silent, nothing it does throws or rejects, it
never reports its own failures, identical reports within a second are
collapsed, and it stops after 20 reports (200 console lines) per context with a
single notice that the rest were dropped.

## Worker WebSocket transport

A Manifest V3 background worker cannot open a WebSocket on WebKit 27. The
engine's worker-side WebSocket channel synchronously posts bridge setup to the
WebContent main thread and then waits on it, and because that thread is also
where extension worker callbacks run, constructing the socket stops the whole
process — every popup and extension page sharing it included. The native
constructor is therefore never reached from a worker; the socket is opened in
the browser process instead and driven from the worker over the capability
broker. Page contexts keep WebKit's own implementation, and so does a worker on
a build where the engine defect is absent.

The worker half is a `WebSocket`-shaped class installed over the global before
the authored worker loads (`BrowserExtensionWorkerWebSocketCompatibilityScript`,
spliced into the generated runtime). Each socket opens one
`runtime.connectNative()` port to the broker and owns it: the port's lifetime is
the connection's, and losing the port is how the socket learns it died.

The envelope, worker to broker:

| Message | Meaning |
| --- | --- |
| `{api: "websocket.open", url, protocols}` | Open the connection |
| `{api: "websocket.send", text}` | Send a text frame |
| `{api: "websocket.send", binaryBase64}` | Send a binary frame |
| `{api: "websocket.close", code?, reason?}` | Start the closing handshake |

And broker to worker, every message an `{api: "websocket.event", kind: …}`:

| `kind` | Payload |
| --- | --- |
| `open` | `protocol`, `extensions` |
| `message` | `text` or `binaryBase64` |
| `sent` | `bytes` — one send left this side |
| `error` | none; the connection is failing |
| `close` | `code`, `reason`, `wasClean` |

The broker refuses a request by throwing, which drops the port, and the worker
half turns that disconnect into the `error` and `close` (1006) pair a failed
handshake produces in any browser. That is also what a worker sees when
`connectNative` is unavailable, which is the whole of the fallback: there is no
second implementation to fall back to.

WebKit never sees this connection, so it cannot apply the extension's content
security policy to it. The broker evaluates `connect-src` — falling back to
`default-src`, and allowing everything when the manifest declares neither, as
Chrome's default `extension_pages` policy does — before opening the socket
(`BrowserExtensionWebSocketPolicy`, Foundation-only and unit-tested). Scheme
matching follows Chromium: `ws:` covers a secure socket, `wss:` never covers an
insecure one, and `https:` covers no socket at all. A source that names no
scheme is the one deliberate divergence: Chromium compares it against the
page's own scheme, which for an extension is `chrome-extension:` and so matches
no socket, and reproducing that would break packages whose author plainly meant
the socket. A non-`ws(s)` URL is refused before the policy is consulted.

Limits worth knowing:

- **No cookies, no credentials, no cache.** Each socket gets its own ephemeral
  `URLSession` with the cookie jar, credential store, and URL cache removed. An
  extension socket carries the extension's own credentials in its payload.
- **The `Origin` header is the extension's Chrome-style origin**
  (`chrome-extension://<store id>`), which is what a local app server
  allow-lists. It is derived from the per-Space client identity rather than
  read off the context's base URL, so it stays correct for a Space that ever
  has to fall back to a hashed per-Space host.
- **Binary is base64.** Native-messaging payloads are JSON, so every binary
  frame is encoded in both directions. A `Blob` sent from the worker is read
  first and queued so it cannot be overtaken by a later `send`.
- **`bufferedAmount` is approximate.** The worker adds a frame's byte length on
  `send` and subtracts it again on the broker's `sent` acknowledgement, so it
  reports bytes handed over and not yet confirmed. It cannot see the socket's
  own kernel buffer — neither can the real property — and a close resets it.
- **`extensions` is whatever the handshake response carried.**
  `URLSessionWebSocketTask` does not report negotiated extensions, so the value
  is read from `Sec-WebSocket-Extensions` and is otherwise empty.
- **A close the worker starts is reported clean.** `URLSession` does not
  distinguish a peer that echoed the closing frame from one that dropped the
  socket after it. A close the *peer* starts carries its own code and reason.

`BrowserNativeMessagingTests` drives `websocket.open/send/close` through a
capability-broker connection against a Network.framework echo server, and
`BrowserExtensionWorkerWebSocketCompatibilityScriptTests` runs the worker half
in WebKit against a fake port.

## Request interception broker — required, not implemented

A JavaScript overlay cannot honestly implement blocking `webRequest`. The
extension must synchronously decide whether a page resource is allowed,
redirected, or modified before WebKit sends it, and response headers may need a
second decision before delivery. Injecting hooks into the DOM occurs after the
network boundary and cannot cover subresources, workers, redirects, or response
headers reliably.

Full uBlock Origin support therefore requires a native, permission-checked
request interceptor with:

1. one compiled policy snapshot per extension and Space;
2. synchronous request and response decisions with bounded latency;
3. exact `webRequest` listener filters, ordering, and extra-info semantics;
4. cancellation, redirect, request-header, response-header, and authentication
   outcomes;
5. a cache invalidated by `handlerBehaviorChanged()`, filter updates,
   permission changes, and extension unload;
6. complete coverage for the main document, subresources, redirects, workers,
   and extension-initiated traffic without escaping Space isolation;
7. diagnostics that distinguish an unsupported action from a rule that simply
   did not match.

Orion's public Debug menu exposes both a **Policy Cache** for WebRequest
blocking and a **Resource Interceptor**, which is strong evidence that its
uBlock support also crosses this native request boundary. It does not disclose
an implementation Crest can copy. Until Crest has a public WebKit hook capable
of enforcing the contract—or deliberately maintains a reviewed WebKit fork—the
full Firefox uBlock gate remains incomplete. A helper process can compile and
evaluate policies, but it cannot intercept traffic by itself; the WebKit host
still needs an enforceable request hook.

## App-side service layout

Notifications, side panels, tab groups, and framed-site cookies have
Application-layer service ports. Other broker capabilities are implemented
where their state lives.

| Concern | Where it lives | Shape |
| --- | --- | --- |
| Notifications | `CrestShared/Domain/BrowserExtensionServices/Notifications/`, `CrestShared/Application/BrowserExtensionServices/Notifications/`, `CrestShared/Infrastructure/BrowserExtensionServices/Notifications/`, `CrestMac/Infrastructure/BrowserExtensionServices/` | Full port/adapter/double service: `BrowserExtensionNotificationHandling` and `BrowserExtensionNotificationCentering` ports, `BrowserExtensionNotificationService`, the `BrowserExtensionNotificationSystemCenter` platform adapter, and the `InMemoryBrowserExtensionNotificationCenter` double |
| Side panels | `CrestShared/Domain/BrowserExtensionServices/Sidebar/`, `CrestShared/Application/BrowserExtensionServices/Sidebar/`, `CrestShared/Infrastructure/BrowserExtensionServices/Sidebar/`, `CrestMac/Features/ExtensionSidebar/` | `BrowserExtensionSidebarHandling`, observable store, behavior persistence adapters, per-window host and native document |
| Tab groups | `CrestShared/Domain/BrowserExtensionServices/TabGroups/`, `CrestShared/Application/BrowserExtensionServices/TabGroups/`, `CrestShared/Infrastructure/WebKit/BrowserExtensions/BrowserExtensionTabWindowCoordinator+TabGroups.swift` | `BrowserExtensionTabGroupHandling` port, observable store over a Space-scoped registry, and an async event hub that fans one change out to every extension in the Space. No persistence adapter: Chrome's group ids are session-local too |
| Declarative header rules | `CrestShared/Domain/BrowserExtensionServices/DeclarativeNetRequest/`, `CrestShared/Application/BrowserExtensionServices/DeclarativeNetRequest/`, `CrestShared/Infrastructure/BrowserExtensionServices/DeclarativeNetRequest/`, `CrestShared/Infrastructure/WebKit/BrowserExtensions/BrowserExtensionTabWindowCoordinator+DeclarativeNetRequest.swift` | `BrowserExtensionDeclarativeNetRequestHandling` port, observable store keyed by extension and Space, an event hub per client, and `UserDefaults`/in-memory persistence adapters for the dynamic ruleset |
| Framed-site cookies | `CrestShared/Domain/BrowserExtensionServices/CookieAccess/`, `CrestShared/Application/BrowserExtensionServices/CookieAccess/`, `CrestShared/Infrastructure/BrowserExtensionServices/CookieAccess/`, `CrestMac/Infrastructure/WebKit/BrowserExtensions/BrowserExtensionCookieJarCoordinator.swift` | `BrowserExtensionCookieAccessHandling` and `BrowserExtensionCookieJarRelaxing` ports, an observable store keyed by client and Space, the `BrowserExtensionCookieJarCoordinator` WebKit adapter, and the `InMemoryBrowserExtensionCookieJar` double. No persistence adapter: the relaxation follows a live page, so a launch that never frames the site again relaxes nothing |
| Idle state | `CrestMac/Infrastructure/WebKit/BrowserNativeMessagingService.swift` | `BrowserExtensionIdleWatch` reads macOS session and input state directly inside the broker connection; there is no port and no separate service type |
| Context menus and install lifecycle | `CrestShared/Infrastructure/BrowserExtensions/ContextMenus/BrowserExtensionWebpageMenuRegistry.swift` with `CrestMac/Infrastructure/WebKit/BrowserExtensionWebpageMenuProvider.swift` | A registry and a platform menu provider reached over the same broker transport, not an Application-layer service |
| Offscreen documents and downloads | `CrestShared/Infrastructure/WebKit/BrowserExtensions/` | Answered by the tab/window coordinator and page provider, because both need live WebKit and Crest browser state |
| Debugger | `CrestShared/Domain/BrowserExtensionServices/Debugger/`, `CrestShared/Application/BrowserExtensionServices/Debugger/`, `CrestMac/Infrastructure/WebKit/Inspector/` | `BrowserExtensionDebuggerHandling` port over a WebKit-Inspector-backed session store; the shell supplies the consent gate and target resolver in `BrowserExtensionDebuggerInstallation` |
| External web-page messages | `CrestShared/Domain/BrowserExtensionServices/ExternalMessaging/`, `CrestShared/Application/BrowserExtensionServices/ExternalMessaging/`, `CrestShared/Infrastructure/WebKit/BrowserExtensions/BrowserExtensionTabWindowCoordinator+ExternalMessaging.swift`, `CrestMac/Infrastructure/WebKit/BrowserExtensions/` | `BrowserExtensionExternalMessageHandling` port over a registry of watch ports and pending one-shot replies, owned by the tab/window coordinator; `BrowserExtensionWebPageRuntimeRelay` is the page-facing half. No persistence adapter: a delivery outlives nothing |

There is no history, top-sites, web-authentication, or omnibox service in the
tree. The design notes for those are kept at the end of this document, marked
as unbuilt.

Domain values live under `CrestShared/Domain/BrowserExtensionServices/`. The
Application layer may import only Foundation, Dispatch, and Observation, so
every framework seam is expressed in Crest's own types and implemented in a
platform root. A new service adopts the notifications shape: a port protocol,
an adapter behind it, and an in-memory double that ships in the app target so
tests, SwiftUI previews, and isolated launches all use the same seam.

Extensions are identified to these services by
`BrowserExtensionServiceClientID`, an opaque non-empty string. It is deliberately
not `BrowserChromeExtensionID`, which only accepts 32-character Web Store
identifiers and so cannot name an unpacked development extension.

## Side panels — `chrome.sidePanel` and `browser.sidebarAction`

Both APIs share a per-client options registry and one selected document per native
window and Space. Chrome tab-specific options choose the resource when opened;
Firefox title, icon, and panel options inherit through tab, window, and default layers.
The coordinator validates native tab/window identities and gesture eligibility
before changing the store. `sidebar.watch` is a permission-checked event stream
separate from notification and idle watches.

The macOS host presents a trailing split-row card backed by an extension
`WKWebView`, never a tab adapter. Selecting another extension replaces the current
panel throughout the Space. Switching tabs keeps the document mounted; native
tab events update the extension's active-page context. Switching Spaces hides
the document and restores that Space's selected panel. Closing, replacing,
locking, or uninstalling releases the document. Disabling an option prevents
new opens without dismissing an ongoing panel. Width and last-used client are local
window preferences; action behavior persists per client. Open intent and
runtime options do not survive relaunch. Firefox fresh-install opening is
consumed once when the host becomes available, not on restoration.

The card header names the selected extension. There are no per-tab panel
selections, scope labels, or tab/toolbar panel indicators. Closing a panel cannot
reveal an older selection. Removing the tab used to open a resource does not
close the panel, and a Space with no tabs can keep its current panel. This
presentation deliberately differs from Chrome's contextual-panel switching.

The resident webpage receives the reduced card viewport as the panel opens or
resizes. Responsive pages retain the requested zoom. An authored document/body
CSS minimum width can temporarily reduce the displayed zoom to fit, bounded by
the normal zoom floor; closing the panel restores the requested zoom. This does
not rewrite the saved zoom or fit intentionally scrollable tables and carousels.

Top-level web URLs open through Crest's tab path. Sidepanel and offscreen
documents use a private content controller applied to each navigation, including
embedded websites, through WebKit's `_setUserContentController:` webpage preference.
The native extension controller remains attached for the owner's origin, APIs,
and background messaging; its shared scripts, styles, and content rules are
excluded from the hosted document. New injections after opening are excluded too.
The external website relay admits only the owning extension. Ordinary browser
tabs and WebKit-owned popups retain their existing controllers. If the isolation
SPI is unavailable, Crest refuses to load the hosted document.

The navigation delegate receives WebKit's own preferences copy. Mutating the
configuration's default preferences would also change other views because
`WKWebViewConfiguration.copy` shares that object. Hosted documents still use the
existing CSP compatibility policy described below. Packaged path icons are supported, while
`sidebarAction.setIcon({imageData})` rejects rather than reporting success.
The compatibility matrix hides WebKit's partial namespaces and publishes the
complete Chrome and Firefox member lists only in privileged extension contexts.

## Tab groups — `chrome.tabGroups`, `tabs.group`, `tabs.ungroup`

One registry per Space, shared by every extension in it, because Chrome's
groups are browser-wide rather than per package: an extension can read and
update a group another extension created. `windowId` is always that Space's
primary extension window — the compatibility runtime resolves the number from
the native `windows.getCurrent()` rather than inventing an identifier, exactly
as the sidebar fragment does, and the broker names the window only by kind.
`tabGroups.watch` is a permission-checked event stream separate from the
notification, idle, and sidebar watches. `tabGroups.*` require the `tabGroups`
permission. `tabs.group`, `tabs.ungroup`, and the `Tab.groupId` mirror require
a verified extension context in the owning Space, with no additional manifest
permission. Chrome's `tabs` permission controls sensitive tab properties rather
than access to ordinary tab operations; WebKit still filters those properties.

The coordinator re-verifies every tab target against the live Space before the
registry moves — the wire carries a tab index and the URL JavaScript saw, never
a WebKit identifier — and a transient page such as a Peek is excluded, so it
can never join a group. `reconcile(session:)` repairs the registry on every
session change, dropping closed tabs and emitting `onRemoved` for a group its
last tab has left.

WebKit can return an empty URL when sensitive metadata is withheld. The
compatibility runtime omits that unavailable identity hint instead of comparing
it with the live URL and rejecting a valid tab. Native tab lookup and owning-Space
validation still apply. Explicit `chrome://newtab` and `chrome://newtab/` requests
when creating a tab or a normal window use Crest's native start page.

Groups project the same folder tree displayed in Saved and Current Tabs. The
browser family shares one service across windows; the session restores membership,
names, colors and collapse state. Moving a populated folder between sections
preserves its extension group ID as well as its folder ID.

- Dropping a current tab onto another tab creates a folder; the tab context menu
  also creates folders or adds tabs to existing ones. Folder headers support
  dropping tabs, renaming, color changes, collapse and ungrouping.
- `tabs.group` and UI changes use the same membership. Members occupy one
  contiguous run. A split view remains one row and joins as a whole.
- New extension groups use the first requested tab's Saved or Current placement.
  Adding tabs to an existing group uses that folder's placement. Ungrouping
  preserves each tab's section and saved URL. Pinned and transient tabs remain
  ineligible for grouping. Grouping and ungrouping reconcile native tab order
  before replying with membership indexed against the updated session.
- `tabGroups.move` moves the complete run and emits `onMoved`; it refuses a
  destination that would split another group or insert into a different folder
  hierarchy. Group indexes use the Space's primary extension window; an index
  in another section moves the folder there. Native tab order and folder order
  change in the same session transaction. Cross-Space group moves remain unavailable.
- `Tab.groupId` is projected onto every `tabs.get` and `tabs.query` result from
  a mirror the broker refreshes. Concurrent reads share the same refresh.
  Folders created by the user or another extension are visible without an
  opt-in or sensitive-tab permission. The internal response contains tab indexes, opaque identity tokens, a change
  revision and group IDs, not names, URLs or titles.
- `tabs.move` commits numeric-index moves through the same placement and folder
  model. Single and multiple tab requests preserve selection and pinned state;
  moving within a group keeps membership, and insertion between two members
  joins their group. A singleton leaf folder moves with its identity. Results
  are read back through WebKit so native tab IDs and sensitive-property access
  remain authoritative. Only the Space's normal window accepts moves; auxiliary
  windows and cross-Space destinations are refused. Nested folder boundaries
  remain subject to the shared tree's movement constraints.
- Native `tabs.onCreated` and `tabs.onUpdated` tab objects receive group metadata.
  Folder membership changes also deliver `tabs.onUpdated(tabId, {groupId}, tab)`
  through a separate, permission-free metadata watch. The store emits ordered
  changes for surviving tabs, independently of group visual events. Before
  correlating opaque session tokens with WebKit IDs, the runtime checks the host
  revision around a native tab query; moving away and back invalidates that
  attempt. Closed tabs are skipped and native getters retain sensitive-property
  filtering. The original event objects and listener removal remain intact.
  Metadata unavailable during a native event never suppresses that native event.
- `TabGroup.shared` is always `false`. Chrome's shared and saved groups are a
  sync feature Crest has no equivalent for, and reporting `false` is the truth
  rather than a stub.
## Context enumeration — `chrome.runtime.getContexts`

WebKit's runtime IDL publishes no `getContexts` and none of Chrome's `runtime`
enums, so a package that reads `runtime.ContextType.SIDE_PANEL` or compares an
install reason against `runtime.OnInstalledReason.INSTALL` throws where it
expected a string. Crest publishes every enum the pinned Chromium
`runtime.json` declares, frozen and member for member, and answers
`getContexts` through the capability broker from the document registries it
actually owns.

`runtime` gates on no permission in Chrome and asks for none here: the handler
requires only that the calling context is authorized to use the internal
broker, the same reasoning that lets `diagnostics.report` past the grant table.

Three context types are covered:

- `SIDE_PANEL` — every side-panel document Crest currently has loaded for the
  extension in the Space, reported with the document's live URL. Extensions
  read their own query string back off `documentUrl` to recognize a panel, so
  the document registry answers here, not the stored options. A tab-scoped
  panel names its tab; a Space-wide panel reports `tabId: -1`.
- `OFFSCREEN_DOCUMENT` — the Crest-hosted offscreen document, if the extension
  has one in the Space.
- `BACKGROUND` — one entry when the package has background content.
  `documentUrl` follows the package's own declared manifest, so an MV3 worker
  reports none and a background page or MV2 `scripts` background reports the
  page URL. Crest's hosting choice does not leak through it.

`POPUP`, `TAB`, and `DEVELOPER_TOOLS` are absent rather than guessed at:
those documents live inside WebKit's page lifecycle, which publishes no
enumeration Crest can read. `documentId` is likewise never reported, so a
filter on `documentIds` matches nothing. `incognito` is always false — a
private Space loads no extension controller. Tabs and windows cross the broker
as a Space-relative tab index plus that tab's URL, exactly as the sidebar event
channel reports them, and the page-side wrapper resolves them back to WebKit's
numeric IDs through `tabs.query` before applying the complete `ContextFilter`.

## Badge color and toolbar settings — `chrome.action`

`action.setBadgeTextColor` is validated the way Chrome validates it — a CSS
color string or four integers in 0…255, with an optional `tabId` — and then
accepted without changing anything the user sees. Crest draws its own toolbar
badge, and packages call this inside a `try` that reads a throw as "badges are
broken". `action.onUserSettingsChanged` is a real listener registry that never
fires: Crest has no toolbar-pinning change wired to extensions, so the matrix
routes it `presenceOnly` and a future WebKit implementation displaces it rather
than the other way round. Both are aliased onto `browserAction`.

## Declarative rules — `chrome.declarativeNetRequest`

WebKit implements this namespace's methods and publishes none of the schema's
enums or numeric limits, so a rule builder that reads
`RuleActionType.MODIFY_HEADERS` or `HeaderOperation.SET` while composing a rule
throws. Crest adds every enum and constant the pinned Chromium
`declarative_net_request.webidl` declares, in place on WebKit's own namespace
object, and only when WebKit published that namespace at all: a namespace
carrying constants and no `updateDynamicRules` is worse than an absent one.

### Header rules WebKit refuses

WebKit validates every `modifyHeaders` header name against a fixed list of
standard names — `isHeaderNameValid` in
`_WKWebExtensionDeclarativeNetRequestRule.mm` — and rejects the **whole rule**
when one name is missing: *"Rule with id 1 is invalid. The header
`anthropic-client-platform` is not recognized."* A custom header can never pass,
and the standard headers in the same rule go down with it. Chrome applies such a
rule to every request the extension makes, and packages depend on that: the
official Claude extension sets `anthropic-client-platform` and
`anthropic-client-version` on `https://api.anthropic.com/*` at worker startup,
and without them the Messages API answers *"CORS requests are not allowed for
this Organization because of its settings."*

So Crest partitions the rule rather than dropping it.
`updateSessionRules` and `updateDynamicRules` are wrapped in the compatibility
runtime. For each added rule whose `action.type` is `modifyHeaders`,
`action.requestHeaders` is split against
`BrowserExtensionDeclarativeNetRequestHeaderPolicy.webKitAcceptedHeaderNames` —
one Swift constant copied verbatim from WebKit at the matrix's pinned revision
and serialized into the runtime. WebKit receives the rule with only the header
operations it accepts; `responseHeaders` are never touched. A rule left with no
header operation at all is not sent, because WebKit requires one. Everything
rejected is recorded as an **emulated header rule** carrying the rule's `id`,
`priority`, and condition. `removeRuleIds` applies to both halves, and
`getSessionRules`/`getDynamicRules` merge the emulated operations back into
their rule ids so the extension reads back what it set. If WebKit refuses the
native call for any other reason, that error reaches the extension unchanged
and nothing is recorded.

The rules are set by the worker and needed by the side panel, popup, options
page, and offscreen documents, so the table lives on the Swift side, per
extension **and** Space, in `BrowserExtensionDeclarativeNetRequestStore`. Three
broker envelopes carry it, all gated on `declarativeNetRequest` or
`declarativeNetRequestWithHostAccess`:

| Envelope | Direction | Shape |
| --- | --- | --- |
| `dnr.setEmulatedHeaderRules` | one-shot | `{api, ruleset: "session" \| "dynamic", rules: [rule]}` → `{ok: true}`. The runtime applies remove/add itself and sends the resulting ruleset, so the broker replaces rather than merges |
| `dnr.emulatedHeaderRules` | one-shot | `{api}` → `{rulesets: {session: [rule], dynamic: [rule]}}` |
| `dnr.watch` | watch port | pushes `{api: "dnr.event", rulesets: {session: [rule], dynamic: [rule]}}` on every change |

A `rule` is Chrome's own vocabulary — `{id, priority, condition, requestHeaders}`
— so the stored, persisted, and merged-back forms are one representation.
Session rules are cleared when the extension's context unloads or reloads, as
they are in Chrome; dynamic rules survive a relaunch through
`BrowserExtensionDeclarativeNetRequestPersisting`, with a `UserDefaults` adapter
and an in-memory double.

### Applying them

Every extension execution context the runtime already instruments — the
background bootstrap document and extension pages, never a content script —
wraps `fetch` and `XMLHttpRequest.open`/`setRequestHeader`/`send`. Each context
reads the table once at start through `dnr.emulatedHeaderRules` and subscribes
to `dnr.watch`; a request issued before the first table arrives is not modified,
which is safe because the worker sets its rules long before a panel exists.

A request is treated as resource type `xmlhttprequest`. A rule whose
`resourceTypes` names neither `xmlhttprequest` nor `other` does not apply, and
`excludedResourceTypes` and `requestMethods` are honoured.
`urlFilter` implements Chrome's grammar — `||` host anchor, `|` start/end
anchors, `*` wildcard, `^` separator (any character outside
`[A-Za-z0-9_\-.%]`, or the end of the URL), case-insensitive unless
`isUrlFilterCaseSensitive` — and `regexFilter` compiles to a `RegExp`, matching
nothing if it will not compile. `set` replaces, `append` appends
comma-separated per HTTP, `remove` deletes; one operation wins per header name,
the highest `priority` first and the lowest rule id among ties.
`BrowserExtensionEmulatedHeaderRuleMatcher` is the reference implementation of
that grammar and the two are pinned by the same cases.

**Scope.** Only requests the extension itself makes are covered. A content
script's `fetch` runs on the page's origin and is untouched, as is anything a
web page requests; a genuine `webRequest`-class interceptor is the only way to
reach those, and it is the unbuilt work described earlier in this document.
Headers the Fetch standard forbids a script from setting — `User-Agent`,
`Host`, `Origin`, `Cookie`, `Referer`, `Sec-*`, `Proxy-*`, `Content-Length`,
`Connection`, and the rest — are skipped, so an extension cannot change its
user agent this way. `XMLHttpRequest` can only add to a header list, so a `set`
over a header the caller already sent, and any `remove`, are skipped there too.
Under console capture each skip is reported once per header name as
`dnr.emulatedHeaders.skipped`, and each application once per host and header
set as `dnr.emulatedHeaders.applied` — header **names** only, never values.

## Framed-site cookies — no namespace

The only service with no JavaScript surface and no broker envelope. It is not
an API an extension calls; it is a rule Crest applies on the extension's behalf
when one of its own pages frames a site, because WebCore decides `SameSite`
from the top document and leaves no embedder seam. What the rule is, what it
costs, and why it is bounded to the Space are in *Cookies for sites an
extension frames* in `Documentation/ExtensionCompatibility.md`.

The shape follows the other services, with the port split in two so no
Foundation-only layer has to name WebKit:

| Piece | Type | Responsibility |
| --- | --- | --- |
| Domain | `BrowserExtensionCookieAccessPolicy` | Pure functions over `HTTPCookie`: `host(for:)` accepts only `http`/`https`; `appliesTo(cookie:host:)` is RFC 6265 domain matching with the leading dot stripped; `restrictsCrossSiteUse(_:)` recognizes only `Lax` and `Strict`; `relaxed(_:)` returns a copy without `SameSite`, or `nil` when there is nothing to write |
| Application port | `BrowserExtensionCookieAccessHandling` | `relaxCookies(for:client:in:)` and `unregister(client:)`. There is no `register`: a client appears the first time it frames a permitted site |
| Application port | `BrowserExtensionCookieJarRelaxing` | `relax(host:in:)` and `observe(spaceID:onChange:)`, the jar expressed without WebKit. A `nil` handler removes the observation |
| Application store | `BrowserExtensionCookieAccessStore` | Relaxed hosts per client per Space, and the only thing that knows a Space's full host set — so it, not the jar, decides what a change notification re-applies |
| Infrastructure double | `InMemoryBrowserExtensionCookieJar` | Records `relax` calls and can stand in for a third-party write with `simulateCookieChange(in:)` |
| Infrastructure adapter | `BrowserExtensionCookieJarCoordinator` (CrestMac) | Resolves the Space's `WKWebsiteDataStore` from its extension controller, rewrites through `WKHTTPCookieStore`, and owns the `WKHTTPCookieStoreObserver` |
| Trigger | `BrowserExtensionFramedSiteCookieAccess` (CrestMac) | Held by the side panel and offscreen documents; in `decidePolicyFor` it checks subframe, scheme, and `hasAccessToURL:`, then awaits the rewrite before allowing the navigation |

Two details keep the observer from chasing its own writes. `relaxed(_:)`
answers `nil` for a cookie that already places no cross-site restriction, so a
second pass writes nothing at all — and WebKit reports an unspecified
`SameSite` as `none` rather than as no value, which is why the check is a
policy question rather than a nil test. On top of that, the coordinator
suppresses notifications raised during its own pass and re-reads once
afterwards if any arrived, so the login response that establishes a session is
never the one that gets dropped.

`unregister` runs from `unregisterNativeMessagingIdentity`, beside the sidebar,
tab-group, declarative-rule, and debugger unregisters, and stops enforcing a
host only once no client in that Space still lists it.

## External web-page messages — `runtime.onMessageExternal`

WebKit already routes a website's `runtime.sendMessage(extensionID, …)` into an
extension, and Crest adds nothing when it does. It stops routing in one place:
`WebExtensionContext::runtimeWebPageSendMessage` resolves the sending page
through `getTab(senderPageProxyIdentifier)` and drops the message when that
lookup fails. A frame inside a Crest-hosted extension document — the vendor web
app a side panel frames, or a site inside an offscreen document — never
resolves to a tab, and Chrome's side panel is not a tab either, which is why
`sender.tab` is undefined for these deliveries there. The page's promise
settles as a bare `undefined` after a delay. Claude's Cowork panel is the
concrete case: the framed app asks the worker for `get_sidepanel_host_info`
over `externally_connectable`, hears nothing, and reports that it cannot reach
the extension.

Crest carries those deliveries itself over the same in-process broker. Three
envelopes:

| Envelope | Direction | Payload |
| --- | --- | --- |
| `runtime.watch` | context → broker, on the watch port | none. Connected when the first `onMessageExternal` listener is added and disconnected when the last one goes |
| `runtime.externalMessage` | broker → context | `requestId`, `message`, and `sender` as `{url, origin, frameId}` — Chrome's sender for a page that is not a tab: no `tab`, and no `id`, because the sender is a website |
| `runtime.externalMessageReply` | context → broker, one-shot | `requestId`, and `response` when a listener answered. An omitted `response` is Chrome's "the receiving end does not exist" |

The watch asks for no permission grant, only the broker authorization the port
already holds, for the same reason `runtime.getContexts` and
`diagnostics.report` do: no `chrome.*` permission stands in front of
`onMessageExternal` in Chrome either. Every context of the extension opens its
own port and hears every delivery, as it would natively; the first listener to
claim a message owns the answer and a later one is dropped, exactly as Chrome
drops a late `sendResponse`. A delivery a listener claims but never answers,
and one that reaches an extension whose worker was evicted mid-dispatch, ends
at 30 seconds with the same "receiving end does not exist" rather than holding
the page's promise for the life of the panel.

Whether the page was allowed to send is decided on the Swift side, before any
of this: see *Externally connectable web pages* in
[`ExtensionCompatibility.md`](ExtensionCompatibility.md). Payloads are never
logged — an OAuth hand-back carries an authorization code — only outcomes and
byte counts.

`BrowserExtensionExternalMessagingCompatibilityScript` is the extension half,
spliced into the generated runtime beside the identity fragment; it dispatches
through the same listener wrappers a native delivery runs through, so
`return true` plus `sendResponse`, a returned Promise, and a synchronous answer
all behave as they do natively.

## Debugger — `chrome.debugger`

WebKit publishes no debugger namespace and drops the `debugger` permission, so
Crest owns the whole surface: the namespace, the decision, the prompt, and the
transport. The namespace is published complete — `attach`, `detach`,
`sendCommand`, `getTargets`, `onEvent`, `onDetach`, and the frozen
`DetachReason` and `TargetInfoType` enums — because the ChatGPT and Claude
packages both read `chrome.debugger.onDetach` at worker startup and lose the
rest of their bootstrap when it is missing.

Only `{tabId}` debuggees are supported. `extensionId` and `targetId` targets
report `Cannot attach to this target.`, and every validation message is
Chrome's own text, including the interpolated tab id, because packages branch
on those strings.

### What the protocol answers today

| Domain | Implemented |
| --- | --- |
| `Runtime` | `enable`, `disable`, `evaluate`, `callFunctionOn`, `awaitPromise`, `getProperties`, `releaseObject`, `releaseObjectGroup`, plus `executionContextCreated`/`executionContextDestroyed`/`executionContextsCleared` events |
| `Page` | `enable`, `disable`, `getFrameTree`, `getLayoutMetrics`, `setLifecycleEventsEnabled`, `navigate`, `reload`, `bringToFront`, `close`, `handleJavaScriptDialog`, `captureScreenshot` |
| `Input` | `dispatchMouseEvent`, `dispatchKeyEvent`, `insertText` |
| `Network` | `enable`, `disable`, `getResponseBody`, translated request/response/loading events |
| `Fetch` | `enable`, `disable`, request/response `requestPaused`, `continueRequest`, unchanged `continueResponse`, request-stage `failRequest`, explicit-body `fulfillRequest`, native-cache `getResponseBody` |
| `Target` | `getTargets`, `closeTarget` |
| `Accessibility` | `enable`, `disable`, `getFullAXTree`, `getRootAXNode`, `getChildAXNodes` using native WebKit accessibility properties |
| `DOM` | `resolveNode` for backend IDs returned by accessibility and DOM snapshots |
| `DOMSnapshot` | `captureSnapshot` with DOM, frame, computed-style and measured layout data |

Unsupported commands and parameters still reject and are logged to
`extension-diagnostics`. `Runtime.evaluate` accepts ordinary WebKit expressions
with `replMode`; V8's top-level await and lexical redeclaration semantics are not
emulated. A positive `timeout` bounds the response wait, including an awaited
promise. **WebKit cannot terminate execution at that deadline.** The timeout
error states that the script may still be running; it does not claim cancellation.
Side-effect-free evaluation constraints remain rejected before running code.

`Page.captureScreenshot` supports PNG/JPEG, integer page-coordinate clips, and
positive fractional clip scales. A clip is also supported with
`captureBeyondViewport: false`, as used by Claude for background tabs. Capturing
does not scroll or resize the target page. Empty clips, excessive output sizes,
`fromSurface: false`, and `optimizeForSpeed: true` reject explicitly.


Accessibility reads return WebKit's computed roles, names, supported states and
DOM-backed tree. Repeated reads share one native document binding; navigation
invalidates old IDs. `DOM.resolveNode` resolves those IDs to native Runtime
objects. Explicit child-frame roots, anonymous platform AX objects, value/source
annotations and AX change events remain unsupported. The adapter does not infer
accessible names from page-defined JavaScript or silently fabricate these fields.

`DOMSnapshot.captureSnapshot` reads ordinary DOM, open/closed shadow roots,
template contents and frames through an owned named content world. Real native
frame IDs link iframe documents. Page-defined JavaScript getters cannot replace
the snapshot's geometry or traversal. DOM and accessibility share native node
bindings. WebKit does not bind whitespace-only text nodes; bounded weak
references in the owned world preserve their stable, resolvable backend IDs
without retaining detached elements. Navigation invalidates both ID types.

Snapshot layout uses element bounds and text Ranges in document coordinates.
Text remains DOM source text; text boxes use measured Unicode character ranges
with UTF-16 offsets, rather than Blink's inline-fragment partition. Stacking
contexts are derived from computed CSS. Native pseudo-elements and anonymous
renderer objects are not exposed. Paint order, DOMRects, blended background
colors and text opacities reject when requested, as do frames in a separate
Inspector target. These rendering limits are not represented by fabricated
zero values. Reads are bounded per frame by node, text, string and elapsed-time
limits; exceeding a limit fails the capture instead of truncating it.

`Page.setLifecycleEventsEnabled` forwards subsequent native main-document
`DOMContentLoaded` and `load` milestones with the actual loader and timestamp.
Disabling it stops those events. WebKit does not supply Chrome's network-idle or
paint milestones here, and previously fired milestones are not replayed.

### Network interception

`Fetch` belongs to the same authorized debugger attachment as the other domains.
URL globs, resource types and request/response stages filter real WebKit
interceptions. Omitted patterns match requests; an empty pattern list does not
intercept. Each pause has a fresh ID mapped to its engine request and stage.
Unmatched resources continue automatically. Repeated enable calls replace the
match set, while disable and session teardown release pending network work.

The transport claims interception events only while the Fetch adapter owns them;
otherwise the borrowed Inspector frontend would automatically continue them
before the extension could respond. Other network/Inspector events keep their
existing delivery path.

Request overrides support URL, method, headers and base64 POST data. Fulfillment
supports explicit base64 bodies at either stage; request-stage fulfillment can
also return an empty body. Authentication challenges, response-stage failure,
redirect fulfillment, duplicate/binary response headers, per-request response
interception overrides and modified `continueResponse` options are not emulated.
They reject instead of reporting success. Response body reads use WebKit's native
resource cache and can fail if the engine has not made the body available; no
streaming body or early-response buffering is provided.

### Binding, consent, and the Stop control

A tab is named once, at attach, by the primary session index and URL the
caller's JavaScript resolved from a native `tabs.get`. Crest re-checks that
pair against live session state, binds the resulting tab to a minted session
token, and every later command addresses the token. Reordering, replacing, or
navigating tabs cannot redirect a live session, and the tab id the caller sends
is used only to reproduce Chrome's error text.

The `debugger` grant is Ask, Allow, or Block per Space. The first attach under
Ask presents a prompt naming the extension and what an attachment means; Allow
persists for that Space and Block refuses without re-prompting. `getTargets`
never prompts — it lists the Space's live tabs and reports `attached: false`
for every one while the grant is missing.

While a session is attached, the page carries a banner above it naming the
extension with a **Stop** control that cancels the session and delivers
`onDetach` with `canceled_by_user`. Revoking the grant, locking the Space,
closing the tab, or navigating to a page the extension has no host access to
withdraws the session immediately rather than at its next command. An explicit
`detach()` emits no event, matching Chrome.

Restricted targets are refused whatever the manifest asks for: Crest's Start
Page (no document), `about:` and `file:` URLs, the extension-install handoff
scheme, another package's extension documents, and the extension storefronts.
Private browsing has no debugger at all.

## Notifications — `chrome.notifications`

`BrowserExtensionNotificationHandling` covers authorization, `create`,
`update`, `clear`, `getAll`, and a per-extension `AsyncStream` of interactions.
The JavaScript surface maps those operations plus `getPermissionLevel`,
`onClicked`, `onButtonClicked`, and `onClosed` through the shared capability
broker. The extension and Space identity come from the verified WebKit context;
extension JavaScript cannot choose another notification owner.

The host notification center is addressed through a second, framework-neutral
port, `BrowserExtensionNotificationCentering`. That split keeps the routing
rules — which extension owns a notification, whether authorization permits a
delivery, who hears about a click — in the Application layer where they are
testable without a real notification center.

**Identity encoding.** Notification identifiers are chosen by untrusted
extension JavaScript and are unique only within one extension, so the host
identifier combines both. A plain delimiter would be forgeable: an extension
could embed the delimiter and address another extension's notification. The
client identifier is therefore length-prefixed in UTF-8 bytes, which makes the
split point independent of either identifier's contents. All of this lives in
`BrowserExtensionNotificationIdentityCodec`.

**Grouping.** Every notification from one extension shares a thread identifier,
so the host collapses them the way it collapses any other app's group. Buttons
force one category per notification, because `UNNotificationAction`s are
declared on categories and every notification may carry different buttons;
categories are withdrawn together with their notification.

**Authorization.** A denied host returns `.authorizationDenied` rather than
throwing. An extension that ignores a rejected promise still behaves
predictably. An undetermined state prompts once, then caches the answer for the
rest of the process.

**Enumeration** reads the host back rather than trusting local bookkeeping, so a
notification the person dismissed from Notification Center disappears from
`getAll`.

## Identity — `chrome.identity`

The namespace has two halves that fail in opposite directions, and the split
is the whole design.

**The portable half — implemented.** `getRedirectURL` and `launchWebAuthFlow`
run an authorization flow against any provider. Chrome does not own
`chromiumapp.org` either: it watches its own web view for the first navigation
to `https://<extension id>.chromiumapp.org` and cancels it, so the redirect
never reaches the network and the code never leaves the browser. Crest does the
same thing in `BrowserExtensionWebAuthFlowHost`.

**The Google-account half — answered, not faked.** `getAuthToken`,
`getAccounts`, `getProfileUserInfo`, `removeCachedAuthToken`, and
`clearAllCachedAuthTokens` are bound to Chrome's own Google sign-in state,
which a Crest profile has none of. They answer the way a Chrome profile with no
Google account answers: an empty account list, an empty `ProfileUserInfo`, a
token cache that really is empty so removing from it really does succeed, and —
for the one call that would have to mint a credential — Chrome's own refusal
text, `OAuth2 not granted or revoked.` when the manifest has an `oauth2`
section and `Invalid manifest: 'oauth2' section is missing.` when it does not.
`onSignInChanged` keeps a real listener registry and never fires.

### Envelopes

One request, one response. `launchWebAuthFlow` is the only member that reaches
the broker at all; everything else is answered inside the compatibility
runtime.

| Direction | Shape |
| --- | --- |
| Request | `{api: "identity.launchWebAuthFlow", url, interactive, abortOnLoadForNonInteractive, timeoutMs}` |
| Response | `{url: "<the redirect URL>"}` |
| Failure | Chrome's own text: `Authorization page could not be loaded.`, `The user did not approve access.`, `User interaction required.` |

The request names no redirect. `BrowserExtensionTabWindowCoordinator+Identity`
derives the origin it watches for from the loaded context's own base URL — the
same string WebKit serves the package's pages from — so an extension cannot ask
Crest to hand it a URL, and the authorization code in it, from an origin it
does not own. `timeoutMs` is clamped to Chrome's 60-second ceiling in
`BrowserExtensionIdentityBrokerRequest` rather than trusted.

### Redirect origin

`getRedirectURL(path)` resolves `path` against
`https://<runtime id>.chromiumapp.org/`, reading `runtime.id` live. A verified
Chrome Web Store package runs at its real store origin, so this is the
`[a-p]{32}` host the provider already has on file and a `prompt=none`
authorization is accepted. Every other package keeps Crest's per-Space host,
which is not a Chrome-shaped id: the round trip still completes, and a provider
that validates the redirect host will refuse the flow, exactly as it refuses an
unpacked extension in Chrome.

Matching is origin equality, not a prefix test. Chrome matches
`https://<id>.chromiumapp.org/*`, so any path, query, or fragment completes the
flow while `…chromiumapp.org.example.com` does not.

### Host behavior

`BrowserExtensionWebAuthFlowHosting` is the port; the macOS implementation
builds a `WKWebView` on **the Space's own `WKWebsiteDataStore`** — the store
the person's tabs and that Space's extension pages already share. That is the
point: a provider the person is signed in to answers a silent re-authorization
without a password Crest has no business seeing.

- The redirect is detected in `decidePolicyFor navigationAction` and
  `decidePolicyFor navigationResponse`, plus
  `didReceiveServerRedirectForProvisionalNavigation` as a backstop. The
  navigation is **cancelled**, the URL is resolved to the extension, and the
  web view is torn down. WebKit reports Crest's own cancellation through
  `didFail`, so a cancelled navigation is never mistaken for a load failure.
- **Non-interactive** never shows a window. A page that finishes loading
  without redirecting fails with `User interaction required.` when
  `abortOnLoadForNonInteractive` is true (the default); when it is false only
  the deadline ends the flow, with the same text. The web view is still hosted
  by an unshown `NSWindow` and configured with
  `inactiveSchedulingPolicy = .none`, because Crest's pages suspend when
  detached from a visible window and the providers this exists for redirect
  from JavaScript.
- **Interactive** presents a 520×720 window titled with the extension's display
  name, centered on the front Crest window, when the first page load completes
  — Chrome's rule, so a flow that redirects straight through never flashes a
  window. Closing it fails with `The user did not approve access.`
- A navigation failure fails with `Authorization page could not be loaded.`,
  which is also what a missing host, data store, or profile reports.
- **One flow per extension.** Chrome queues a second call; Crest refuses it
  with the load-failure text instead. A queued invisible web view is a resource
  an extension can grow without bound, and the packages Crest has seen retry
  rather than wait.

### Security notes

The authorize URL carries the PKCE challenge and the account hint; the redirect
URL carries the authorization code. Neither is ever logged.

- The compatibility runtime's capability trace, which records every broker call
  when console capture is on, treats `identity.launchWebAuthFlow` as sensitive:
  `requestCapability` rewrites any `url` in the traced request or response to
  its origin and path, dropping the query and fragment.
- The Swift side logs nothing about the flow at all. The URL is read once, to
  match the redirect origin, and handed straight back to the calling extension.
- Chrome's failure texts are reproduced exactly and none of them interpolate
  the URL, because an error message is a place a package logs.

**Why not `ASWebAuthenticationSession`.** Its callback is declared up front and
comes in two shapes. `.customScheme(_:)` matches a custom URL scheme, which
Chrome extensions do not use here. `.https(host:path:)` matches a real web URL,
but only for a host the app is *associated* with — a
`com.apple.developer.associated-domains` entitlement naming
`webcredentials:<host>` **and** an `apple-app-site-association` file served by
that host listing Crest's bundle identifier. Crest controls neither
`chromiumapp.org` nor the association file Google would have to publish for it,
so the system would refuse to start the session. Watching Crest's own web view
is the only shape that reproduces Chrome's contract, and it is also the shape
that lets the flow run in the Space's cookie jar.

## Design notes for services not yet built

Nothing below this heading exists in the tree. `chrome.history`,
`chrome.topSites`, and `chrome.omnibox` are all routed **Unavailable** by
`BrowserExtensionAPICompatibilityMatrix`, and no port, service, adapter, or
double for them is present. The notes are kept because the constraints they
work through — Crest's per-Space history shape and the command palette's
synchronous result pipeline — are the real reasons those services are hard, and
rediscovering them later would be waste.

Two store primitives named below did land ahead of their service:
`BrowserSession.removeHistory(...)` and `BrowserStore.deleteHistory(...)`
exist. Everything else is a description of work that has not been done.

### History — `chrome.history` and `chrome.topSites`

Crest has **no history database**. History is a `[BrowserHistoryEntry]` array on
each `BrowserSpace`, owned by `BrowserStore` and persisted as per-Space JSON
under `crest.history.v1.<space-uuid>`. That shapes the whole port.

**Scoping.** Every entry point takes a `BrowserSpaceRuntimeAssignment`, not a
bare `SpaceID`, mirroring how Crest's own history mutations are scoped. A scope
that no longer resolves — a replaced or deleting Space — yields empty reads and
`false` writes rather than silently falling through to the selected Space.

**Fields Crest cannot supply.** Two Chrome fields have no counterpart and are
reported honestly rather than guessed:

- `typedCount` is always `0`. Crest does not distinguish a typed address from a
  followed link.
- `getVisits` returns at most **two** visits — `firstVisitedAt` and
  `lastVisitedAt` — regardless of `visitCount`, because Crest keeps one row per
  URL rather than one row per visit. Transitions are always `link`.

**Deletion.** `deleteUrl` and `deleteRange` did not exist before this work;
browsing only ever appended, and history could only be cleared wholesale. They
are added as `BrowserSession.removeHistory(...)` and
`BrowserStore.deleteHistory(...)`, narrowing the persisted save scope to
`.history(in:)` and staging an explicit-delete tombstone, exactly as
`clearHistory` already did. `deleteRange` judges an entry by its last visit
only: an older visit to a page that was also opened after the window cannot be
removed on its own.

**Change events.** The store publishes none — no Combine subject, no
notification, no delegate. Rather than polling, the service snapshots a Space's
history when an extension first subscribes and re-diffs it whenever Observation
reports that `BrowserStore.sessionRevision` moved. That keeps `onVisited`
working for ordinary browsing, which never calls this service at all. The cost
is coalescing: several visits landing between two observation ticks produce one
event per URL.

**Top sites** are derived on demand by `BrowserExtensionTopSitePolicy`. Raw
visit count alone would pin a site somebody used heavily last spring above one
they use daily now, so counts are weighted by recency — the frecency shape
Firefox popularized.

### Omnibox — `chrome.omnibox`

Crest's address bar renders no suggestions of its own; everything the person
sees comes from `BrowserCommandPalette`. Its sources are `static func`s appended
in a fixed order inside `BrowserCommandPaletteResults.results(for:)`, and before
this work there was no keyword, prefix, or scope concept anywhere in the app.

`BrowserOmniboxRegistry` maps a keyword to a `BrowserOmniboxSuggesting`
provider. One keyword has one owner; re-registering returns the displaced
provider so a caller can tell a genuine refresh from a collision between two
extensions that both want `gh`.

**Activation.** `BrowserOmniboxInput.parse` requires a separating space: `yt` on
its own is still a plain search for those letters, and only `yt ` hands the
address bar over. That matches Chrome and keeps a keyword from hijacking a
prefix the person is still typing.

**Replacement, not addition.** When a keyword resolves, its rows replace every
other source rather than joining them, as Chrome's keyword mode does. This also
means the ordinary result ordering is untouched whenever no keyword matches.

**Async providers in a synchronous pipeline.** `results(for:)` is a pure
synchronous function run on a detached task, and providers are main-actor
isolated and asynchronous. `BrowserCommandPaletteModel` therefore resolves the
provider, awaits its suggestions on the main actor, and passes only values —
`BrowserCommandPaletteOmniboxContext` — across to the detached preparation. The
provider reference never leaves the main actor.

**Acceptance.** Rows carry a `BrowserOmniboxAcceptance` naming their keyword, so
a row prepared under one keyword can never be delivered to whichever provider
happens to be registered by the time it is clicked. Disposition comes from how
the palette was presented — editing an address keeps the result in the current
tab, the new-tab launcher opens a new one — because the palette has no
modifier-aware submit path today.

**Deletable rows** offer *Remove Suggestion* in their context menu, which calls
`onDeleteSuggestion`. A context menu was chosen over Chrome's Shift-Delete chord
because the palette's focused text field consumes that key.

The registry the shipped palette consults is `BrowserOmniboxRegistry.shared`. It
starts empty, so until something registers a keyword the palette behaves exactly
as it did before.

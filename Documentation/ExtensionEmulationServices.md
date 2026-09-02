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
- declared content scripts and every packaged HTML extension page. This
  includes internal routes reached from a popup or options page even when the
  manifest does not name them directly. Manifest sandbox pages are excluded,
  because injecting privileged extension APIs there would violate the sandbox;
- native-first `chrome`/`browser` capability augmentation, namespace-only
  facades for WebKit objects that cannot be extended in place, an exact
  `runtime.getManifest()` fallback, managed-storage empty-policy semantics,
  receiver-safe `runtime.getURL`, empty-message i18n semantics even for a
  non-augmentable native namespace, idle-callback scheduling, optional
  navigation events, `webRequest.handlerBehaviorChanged()` acknowledgement,
  and the broker-backed `idle`, `notifications`, `contextMenus`, `offscreen`,
  and `downloads.download` APIs. The offscreen document is hosted by Crest at
  the URL supplied by the extension.

For a Manifest V3 package that enters this layer, the temporary host manifest
stays Manifest V3. Only its `background.service_worker` path is redirected to a
bootstrap with the same classic-or-module shape. Generated filenames are
content-addressed, so a runtime change forces WebKit to refresh the worker
registration without changing the extension's context identity or storage.
Only the temporary copy is prepared; verified store bytes are never rewritten.

This is the reusable JavaScript/package foundation, not full Chrome parity.
The capability broker currently connects notifications, system idle state,
context menus and the install lifecycle, Crest-hosted offscreen documents, and
`downloads.download`. Of those, only notifications is a port-backed app-side
service; the rest are answered where the state already lives.
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

**One app-side service exists today: notifications.** Everything else the
capability broker answers is implemented where it is used rather than behind a
port, and this section says so plainly so the layout below is read as the
current tree and not as a plan.

| Concern | Where it lives | Shape |
| --- | --- | --- |
| Notifications | `CrestShared/Domain/BrowserExtensionServices/Notifications/`, `CrestShared/Application/BrowserExtensionServices/Notifications/`, `CrestShared/Infrastructure/BrowserExtensionServices/Notifications/`, `CrestMac/Infrastructure/BrowserExtensionServices/` | Full port/adapter/double service: `BrowserExtensionNotificationHandling` and `BrowserExtensionNotificationCentering` ports, `BrowserExtensionNotificationService`, the `BrowserExtensionNotificationSystemCenter` platform adapter, and the `InMemoryBrowserExtensionNotificationCenter` double |
| Idle state | `CrestMac/Infrastructure/WebKit/BrowserNativeMessagingService.swift` | `BrowserExtensionIdleWatch` reads macOS session and input state directly inside the broker connection; there is no port and no separate service type |
| Context menus and install lifecycle | `CrestShared/Infrastructure/BrowserExtensions/ContextMenus/BrowserExtensionWebpageMenuRegistry.swift` with `CrestMac/Infrastructure/WebKit/BrowserExtensionWebpageMenuProvider.swift` | A registry and a platform menu provider reached over the same broker transport, not an Application-layer service |
| Offscreen documents and downloads | `CrestShared/Infrastructure/WebKit/BrowserExtensions/` | Answered by the tab/window coordinator and page provider, because both need live WebKit and Crest browser state |

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

## Design notes for services not yet built

Nothing below this heading exists in the tree. `chrome.history`,
`chrome.topSites`, `identity.launchWebAuthFlow`, and `chrome.omnibox` are all
routed **Unavailable** by `BrowserExtensionAPICompatibilityMatrix`, and no
port, service, adapter, or double for them is present. The notes are kept
because the constraints they work through — Crest's per-Space history shape,
`ASWebAuthenticationSession`'s callback rules, and the command palette's
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

### Web auth — `identity.launchWebAuthFlow`

This is the service with a hard platform constraint, and it is worth stating
plainly.

Chrome extensions almost always pass a redirect URL of the form
`https://<extension-id>.chromiumapp.org/*`. Chrome does not own that domain
either — it watches its own web view and intercepts the first navigation whose
URL starts with the expected prefix.

`ASWebAuthenticationSession` cannot reproduce that. Its callback is declared up
front and comes in two shapes:

- `.customScheme(_:)` matches a custom URL scheme. It needs no configuration,
  and Crest uses it whenever an extension supplies one.
- `.https(host:path:)` (macOS 14.4+) matches a real web URL, but only for a host
  the app is *associated* with. That requires a
  `com.apple.developer.associated-domains` entitlement naming
  `webcredentials:<host>` **and** an `apple-app-site-association` file served by
  that host listing Crest's bundle identifier. The system refuses to start a
  session whose callback fails that check.

Crest controls neither `chromiumapp.org` nor the association file Google would
have to publish for it. An `https` redirect on an unassociated host is therefore
rejected up front with `.unsupportedCallback` rather than started and left to
hang forever. `BrowserExtensionWebAuthenticationService` is constructed with the
set of hosts Crest genuinely is associated with, so legitimate first-party
`https` callbacks keep working.

**Supporting `chromiumapp.org` flows properly needs a Crest-owned
authentication window** that watches navigation the way Chrome does. That is
deliberately not attempted here.

Two checks bracket the session. A callback the system cannot service is refused
before any window appears, and a redirect the system does return is re-checked
against the prefix the extension actually asked for — which keeps a provider
that redirects somewhere unexpected from handing an extension a URL, and any
token in its fragment, that it never requested.

The presentation anchor follows the house pattern: `NSApp.keyWindow ??
NSApp.mainWindow`, resolved before the session starts, held weakly, and a
missing window fails with `.presentationFailure` instead of trapping.

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

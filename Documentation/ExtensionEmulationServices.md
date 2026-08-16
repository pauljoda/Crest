# Extension compatibility runtime and services

WebKit remains Crest's extension engine. It owns package loading, isolated
worlds, content-script timing, permissions, extension origins, CSP, service
workers, Declarative Net Request, and the APIs it already implements. Crest
does not duplicate or replace those security-sensitive engine contracts.

Crest adds a browser-neutral compatibility runtime above that substrate. Its
only job is to fill a missing standard surface or normalize a semantic mismatch
that Crest can implement honestly. Native WebKit members always win; the
runtime only supplies an absent member.

## Architecture contract

1. **WebKit substrate.** `WKWebExtension` and `WKWebExtensionController` keep
   ownership of extension execution and document integration.
2. **JavaScript compatibility runtime.** A generated, versioned runtime is
   loaded before transformed background content, declared content scripts, and
   packaged extension pages. It normalizes the `chrome` and `browser` roots,
   preserves the declared manifest, and provides bounded local adapters where
   no native round trip is needed.
3. **Crest capability broker.** APIs that need application state call one
   permission-checked broker. The broker resolves the extension and Space from
   the loaded context; JavaScript never supplies or overrides that identity.
4. **App-side services.** Notifications, history/top sites, web
   authentication, and omnibox behavior live behind framework-neutral ports.
   They do not import WebKit or know how a package was acquired.

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

- Manifest V3 module workers through a generated nonpersistent background page
  that loads the compatibility runtime before importing the declared module;
- classic service workers by prepending the same generated runtime to the
  temporary worker copy;
- Manifest V2 `background.scripts` by inserting the runtime first;
- declared content scripts and every packaged HTML extension page. This
  includes internal routes reached from a popup or options page even when the
  manifest does not name them directly. Manifest sandbox pages are excluded,
  because injecting privileged extension APIs there would violate the sandbox;
- native-first `chrome`/`browser` namespace overlays, an exact
  `runtime.getManifest()` fallback, managed-storage empty-policy semantics,
  optional navigation events, a cross-context messaging transport, background
  message-startup buffering, and a document-backed offscreen-page adapter that
  uses the URL supplied by the extension.

This is the reusable JavaScript/package foundation, not full Chrome parity.
The app-service broker described below is the next boundary to connect; until a
service is connected, its local adapter must stay bounded or explicitly reject.

Chrome and Firefox packages intentionally remain distinct acquisition formats,
not distinct compatibility runtimes. Chrome commonly supplies Manifest V3
module workers and identifies native hosts through `allowed_origins`; Firefox
can retain Manifest V2 background pages and identifies native hosts through
`allowed_extensions`. Once those declared format differences are normalized,
the runtime selects behavior from API presence and execution context only.

## Cross-context messaging

WebKit's native `runtime.sendMessage` remains the first choice. Crest supplies
a transport only in contexts where WebKit exposes the API but does not carry a
reply reliably between an extension page or content script and an extension's
background content.

- Extension pages use a package-and-namespace-scoped `BroadcastChannel`. The generated
  runtime is present in both the sending page and background document, so this
  path does not cross into website JavaScript. A sender first probes for a
  background receiver. If WebKit has evicted the nonpersistent background, a
  private no-payload native message wakes it; the actual extension message is
  sent only after the receiver finishes its generated background bootstrap,
  answers, and is targeted to that context. This prevents a popup's first
  request from being lost or handled against partially initialized extension
  state while a Manifest V3 module is still starting, without exposing the
  transport signal to extension listeners.
- Content scripts use a reserved, namespace-scoped native `runtime.connect`
  Port. The background marker installed before the compatibility runtime
  identifies the one context allowed to receive those requests and replay them
  to its registered `runtime.onMessage` listeners. The same Port carries
  background `tabs.sendMessage` requests in the other direction. Connected
  content contexts are selected by tab ID and, when supplied, frame ID or
  document ID; the first response wins as it does in Chrome and Firefox.
- Requests preserve callback, Promise, `return true`, and first-response
  behavior. Sender objects preserve the verified runtime ID and page URL; for
  extension pages, the synthesized `origin` matches `runtime.getURL("")` with
  its root slash removed, as browser-origin checks expect. External-extension
  messages continue through WebKit rather than entering Crest's internal
  transport.
- `chrome` and `browser` are bootstrapped independently. When WebKit exposes
  them as different native objects, their channels and reserved Ports remain
  separate so a receiver with no listener cannot claim traffic for the other
  namespace. When WebKit exposes one object through both names, both aliases
  reuse the same route.

The marker and reserved Port name are Crest protocol details, not extension
identifiers. No extension source is inspected or patched, and the transport is
selected by context and available capability alone.

## App-side service layout

Each service is a port protocol with an adapter behind it, and each has an
in-memory double that ships in the app target so tests, SwiftUI previews, and
isolated launches all use the same seam.

## Layout

| Concern | Ports | Service / adapter | Double |
| --- | --- | --- | --- |
| Notifications | `CrestShared/Application/BrowserExtensionServices/Notifications/Ports/` | `BrowserExtensionNotificationService` (Application), `BrowserExtensionNotificationSystemCenter` (CrestMac) | `InMemoryBrowserExtensionNotificationCenter` |
| History and top sites | `CrestShared/Application/BrowserExtensionServices/History/Ports/` | `BrowserStoreExtensionHistoryService` (Application) | `InMemoryBrowserExtensionHistoryStore` |
| Web auth | `CrestShared/Application/BrowserExtensionServices/WebAuthentication/Ports/` | `BrowserExtensionWebAuthenticationService` (Application), `BrowserExtensionWebAuthenticationSystemSession` (CrestMac) | `InMemoryBrowserExtensionWebAuthenticationSession` |
| Omnibox | `CrestShared/Application/BrowserExtensionServices/Omnibox/Ports/` | `BrowserOmniboxRegistry` (Application) plus command-palette integration | `InMemoryBrowserOmniboxProvider` |

Domain values live under `CrestShared/Domain/BrowserExtensionServices/`. The
Application layer may import only Foundation, Dispatch, and Observation, so
every framework seam is expressed in Crest's own types and implemented in a
platform root.

Extensions are identified to these services by
`BrowserExtensionServiceClientID`, an opaque non-empty string. It is deliberately
not `BrowserChromeExtensionID`, which only accepts 32-character Web Store
identifiers and so cannot name an unpacked development extension.

## Notifications — `chrome.notifications`

`BrowserExtensionNotificationHandling` covers authorization, `create`, `clear`,
`getAll`, and a per-extension `AsyncStream` of interactions.

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

## History — `chrome.history` and `chrome.topSites`

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

## Web auth — `identity.launchWebAuthFlow`

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

## Omnibox — `chrome.omnibox`

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

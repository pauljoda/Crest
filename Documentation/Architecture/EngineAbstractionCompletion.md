# Engine abstraction status

Crest has one engine abstraction with two adapters, WebKit and Chromium, and
keeps shared browser rules in the portable core. This document records which
work packages are done and what each still lacks. Read
[ControlPlane.md](ControlPlane.md) for the ownership contract, and follow
`AGENTS.md` for versioning, release notes and tests.

## Ownership

| Layer | Owns | Never owns |
| --- | --- | --- |
| Portable core (`CrestCore`) | Every saved or shared rule that must behave the same on both engines and both platforms: Spaces, tabs, folders, splits, history, archive, sync, access, the downloads ledger and risk, credential capture and save policy, site permission records, search providers, setup and import plans, shortcut conflicts, launch policy, app-wide behavior preferences, media-session arbitration | Rendering, input, scrolling, compositing, engine handles, image bytes, platform services |
| Engine adapters (`CrestShared/Infrastructure/WebKit`, `CrestMac/Infrastructure/WebKit`, `CrestEngines/Chromium`) | Page creation and disposal, loads, navigation history, find, zoom, capture, printing, download transport, permission prompt transport, server trust, HTTP auth transport, popups, media observations, content scripts, DevTools, extension execution | Deciding browser rules; mutating shared state directly |
| Shared Swift (`CrestShared`, `CrestMac`, `CrestMobile`) | Presentation, the Space and tab each window shows, native windows and cards, projections, platform services (Keychain, CloudKit transport, notification delivery, LaunchServices) | Engine types or `#if CREST_CHROMIUM_HOST` outside the adapters; second copies of core rules |

Scrolling, pointer input, compositing, focus and page zoom stay inside the
adapter and never cross the core boundary. A core command owns a saved or
shared transition, and the adapter reports completion. Which Space or tab a
window shows is window state in Swift. Release builds expose the store's
session as a read-only projection. Sync replacements go through the core's
checked transaction, and the session setter that replaces a session directly
exists only in Debug builds, for test fixtures.

Rules every package must keep:

- A Space is one profile. No path may share a profile across Spaces, or create
  a page, transfer, export or network request for a locked Space without a
  grant. The core gate covers commands, native value edits and borrowing; the
  presentation layer must not build content for a locked Space.
- Crest is a single-window app. New windows appear only from a user action or
  an explicit extension `windows.create`. DevTools, popups and side panels
  dock inside the Crest window.
- Capability declarations in `BrowserEngineRegistration` describe what the
  adapter really does, and UI gates on them rather than on build flags.
- Unsupported features have explicit product behavior. Reader, whole-page
  translation and built-in content blocking are unavailable on Chromium by
  decision. Selection translation works on both engines.

## Current state

The core owns the session on every shipping target, and no Swift file still
uses the retired `CREST_CORE_BACKED` flag. On macOS the Chromium composition
(`CrestChromiumUIProduct`, packaged by `package-chromium-host.py --product`)
is the default download on the experimental update channel. The WebKit `Crest`
target is published beside it as the alternate desktop build, and
`CrestMobile` runs WebKit on iPhone and iPad. The Chromium product has its own
engine directory and Safe Storage keychain item, passkeys through the system
sheet, docked DevTools, extensions with side panels and shortcuts, a pinned
strip owned by the Space, and Chrome Web Store installs.

`BrowserPage` (`CrestMac/Infrastructure/Pages`) holds an
`any BrowserPageEngineAdapter` and its `any BrowserPageEngine`. It names no
engine type and has no engine `#if`. The WebKit adapter
(`BrowserWebKitPageAdapter` plus the page's WebKit delegate and bridge
extensions in `CrestMac/Infrastructure/WebKit`) and the Chromium adapter
(`ChromiumPageAdapter` in `CrestEngines/Chromium/Apple`) supply the engine
wiring. `project.yml` selects the entry point, engine registration and
engine-contributed views for each composition by file, and no Swift outside
`CrestEngines` tests `CREST_CHROMIUM_HOST`.

The upgrade path from the WebKit release to the Chromium product is covered by
a test that carries a real installed session, its per-Space history, favicons
and sync journal into the checkpoint. Runs on physical devices and against a
real iCloud account are still outstanding; see WP9.

## Work packages

### WP0. Manual smoke of Chromium-owned surfaces. Remaining

Nobody has recorded the checklist yet. Run it in a review package and mark
each item as works, wrong window or missing: `alert`, `confirm` and `prompt`;
`<input type=file>` with single and multiple selection; a Basic-auth URL;
`<input type=color>`; fullscreen video and Escape; a site notification's
permission and delivery; the PiP button.

What the code does today:

- JavaScript dialogs, before-unload, and HTTP Basic and Digest challenges reach
  Crest's shared `BrowserDialogPresenter` and `BrowserHTTPAuthenticationSession`.
- Page fullscreen reports its state to the shared shell, which shows the video
  without browser chrome and restores the shell on Escape.
- The host has no hook for the file chooser or the color picker, so both use
  Chromium's own engine surfaces. Nobody has verified them in a Crest window.
- Notifications use Chromium's own delivery path.

### WP1. Dead-code sweep. Done, with two leftovers

Removed:

- the `BrowserSession` value-level edit surface
  (`BrowserSession+{Tabs,Organization,Folders,History,DurableTabs,SplitCopies}.swift`
  and `applyCoreEdit`);
- the `crest_core_edit_session`, `crest_session_commit` and
  `crest_session_commit_pair` exports;
- the `transfer.preview`, `batch.preview` and `session.retain` queries, and
  the `records.expired`, `history.visit` and `history.remove_range` policy
  operations;
- `BrowserSyncMaterializer`, `BrowserSyncMergeResolver`,
  `BrowserSyncProjection`, `BrowserSavedSitePolicy`,
  `BrowserExternalLinkLockPolicy`, `BrowserImportDestinationKey`,
  `MobileOnboardingSpaceCarousel` and `MobilePageMenuPrimaryAction`;
- every `CREST_CORE_BACKED` branch and build setting.

Launch cleanup and retention run as the core `records.sweep` command.
`BrowserTabMultiSelectionTests` drives the command path
(`prepareTabBatch` and `commitTabBatch`). `BrowserSession+FolderMigration.swift`
stays, because its Codable path still loads legacy folder membership and
persisted preferences.

Remaining:

- `BrowserShowcaseSessionFactory` and `BrowserPreviewSessionFactory`
  (`CrestShared/Domain/BrowserSession/Fixtures`) have no callers outside their
  own files. Delete them, or move them behind a preview-only compilation path.

### WP2. Page port. Done, with small gaps

Done:

- **Content-script channel.** `BrowserPageContentScripting` installs Crest's
  bridges on Chromium in an isolated world the page cannot reach, and runs
  script in a named document. WebKit keeps installing its bridges through its
  own `WKUserContentController`. Link hover, user activity, blocked popups,
  media sessions and favicons arrive from the Chromium host as typed page
  events.
- **Page split.** The page and its engine-neutral extensions live in
  `CrestMac/Infrastructure/Pages`, with shared page logic in
  `CrestShared/Infrastructure/Pages`. The pool builds each page's adapter
  through an injected `BrowserPageEngineMaker`. The adapter owns the
  engine-built controllers and reports typed `BrowserPageEngineEvent`s and
  `BrowserEngineLinkAction`s. Back and forward menus read
  `backHistory`/`forwardHistory` on both engines. The pool's WebKit hosting is
  `BrowserPagePool+WebKit.swift`. `WKDownload`s run through
  `BrowserWebKitDownloadTransport`, and Media Session keeps one coordinator
  over `BrowserMediaSessionTransport`.
- **Zoom, find and navigation.** The page applies each Space's default zoom
  above the engine fork. Both engines always wrap find. Chromium reports the
  match total and the selected ordinal, and the find bar shows "n of m".
- **Popups.** Chromium relays blocked popups as `popup_blocked`, applies each
  Space's automatic-popup decision as a content setting, and opens the popups
  the blocker held back when the person allows the site. The Chromium
  registration declares `popups` supported.
- **Media.** Chromium reports media-session metadata and transport through
  `BrowserMediaSessionTransport`, and the page can ask Chromium to enter its
  own video Picture in Picture.
- **Favicons and accents.** Chromium supports a manual favicon refresh, and its
  `changed` payload carries `themeColor`.
- **Host commands.** `BrowserEngineHostCommands` gives the Chromium root the
  same store, page and window operations the WebKit menus run.
  `CrestChromiumRoot` and `ChromiumNativePage` do not mutate `BrowserStore`.
  Engine-created pages are adopted through the pool's `adoptEnginePage(_:)`.
- **Viewport fit** was removed rather than ported. Its only caller served the
  retired WebKit extension side-panel card.

Remaining:

- `CredentialContentBridge.swift` in `CrestShared/Infrastructure/Credentials`
  still imports WebKit to install the WebKit credential bridge. Move it into
  the WebKit adapter folder.
- `BrowserPagePool`'s initializer defaults still name WebKit adapter types:
  `WebKitBrowserWebsiteDataStoreRemover` and
  `BrowserContentRuleListProvider`.
- `BrowserPage` builds a `BrowserPopupCoordinator` for every page, and that
  type imports WebKit. `BrowserTransientPageLease`, which Quick Window uses,
  carries WebKit content-rule lists.
- The Chromium extension store and side-panel routing reach
  `CrestChromiumRoot.engineHost`, `extensions` and `activeNativeWindow`
  statically. These are engine-host lookups, not store edits.
- Focus restoration on Chromium relies on the engine's own responder chain.
  Nobody has verified it end to end.
- Quick Window and setup windows have no extension side-panel host.
- `MobileBrowserPage` stays concretely typed over WebKit.

### WP3. Security indicator, certificates and HTTP auth. Done, with one gap

Done:

- Each page carries an engine-neutral `BrowserPageSecurityState` (`none`,
  `insecure`, `secure`, `mixed_content`, `certificate_error`, `dangerous`).
  Chromium reports it in every `changed` payload from
  `SecurityStateTabHelper`. WebKit derives it from the scheme,
  `hasOnlySecureContent`, the trust result on `serverTrust`, and any override
  in `BrowserServerTrustOverrideStore`. Site Controls shows each state and
  offers `View Certificate` whenever the engine hands over its trust.
- Basic and Digest authentication go through the shared
  `BrowserHTTPAuthenticationSession` and prompt on both engines. Proxy
  challenges and other schemes keep the engine's own handling.

Remaining:

- Certificate errors on Chromium show Chromium's own interstitial, and
  proceeding past it is the engine profile's decision. The Chromium
  registration declares this. A proceed-anyway owned by Crest, with the
  override recorded by the core, is not built.

### WP4. Credentials on Chromium. Done

The credential bridge runs through the content-script channel on Chromium, and
fills execute there in Crest's isolated world. Capture, save and recency rules
are core policy operations (WP8). The host turns Chromium's password manager
off for every page it creates or adopts, in Space and private profiles alike,
so Chromium's save and fill bubbles never appear. iCloud Passwords runs through
its extension, and passkeys go through the system sheet.

### WP5. Site permissions, geolocation and notifications. Done, with gaps

Done:

- Permission decisions are records in the core ledger behind
  `crest_permissions_*`. WebKit applies them through Crest's prompts. Chromium
  asks Crest through its permission handler, with a typed
  `BrowserEnginePermissionResponse`, and receives decisions as content
  settings. The Privacy pane lists the same records on both engines.
- Each open page owns one `BrowserPageSitePermissionSession`. A change from a
  prompt, Site Controls or the Privacy pane reaches the page at once through
  `BrowserPageEngine.applySitePermission`. On WebKit, withdrawing a camera or
  microphone grant ends capture through `stopMediaCapture`.
- Clearing site data routes to the engine: `WKWebsiteDataStore` removal on
  WebKit, and the browsing-data remover on Chromium.

Remaining. The Chromium registration declares both limits:

- The host has no command to stop live camera, microphone or location use.
  Revocation relies on Chromium ending capture once the content setting
  blocks it.
- Chromium delivers web notifications itself. Delivery through Crest's
  `UserNotifications`, source-tab activation, and withdrawal of delivered
  notifications after revocation all need a host notification hook.

### WP6. Capability truth and UI hygiene. Done

- `BrowserCommandActions.paletteCommands` and
  `ShortcutCommand.offered` filter by the current engine's
  capabilities.
- Settings destinations filter on `isProvidedByCurrentEngine`, which covers
  Feature Flags.
- When content blocking is unavailable, the Privacy pane says that blocking
  comes from the extensions the person installs.
- Archives follow the engine: `.webarchive` on WebKit, `.mhtml` on Chromium.
  Open File offers only the running engine's format, as
  `BrowserLocalFileOpenPolicy` explains, and the Help Center says so.
- `BrowserCorePolicy.addressIntent` sends `allowsInternalPages` from the
  `internal-pages` capability rather than from a build flag.
- Every declared capability either gates UI or services, or belongs to
  `EngineCapability.Required`, the set (`pages`, `navigation`,
  `workspace-profiles`, `profile-deletion`) the core requires before it
  registers an engine.

### WP7. WebKit symmetry. Done

`BrowserWebKitPageEngine` reports its real PiP activity for residency, stages
Peek navigation with the source request and website data store, and prepares
a page close through WebKit's before-unload path. The staged request carries
the URL and referrer only, because WebKit does not expose the initiating
frame's security context to a second page. The registration declares that
limit and the desktop before-unload SPI dependency. WebKit extensions are
retired, and the WebKit registration declares `extensions` unavailable.

### WP8. Core extraction of the rule aggregates. Done, with small gaps

Each aggregate is core domain and application code with focused tests,
reached through semantic session commands, `crest_core_evaluate_policy`
operations or a bounded export. Swift keeps projections and adapters.

| Aggregate | Core surface |
| --- | --- |
| Downloads | Typed download intents, changes and the `DownloadProgress` and `DownloadRisk` queries on `crest_app_*`; the `downloads.automatic` operation |
| Credentials and passkeys | The `CredentialCapture`, `CredentialFill`, `CredentialSaveCheck`, `MostRecentCredential`, `CredentialSaveMatch`, `CredentialSave`, `StrongPassword`, `PasskeyAccess`, `SystemPasswordWriteThrough` and `SystemPasswordOffer` queries on `crest_app_*`. Passwords never cross the boundary |
| Site permissions and origins | `crest_permissions_*` ledger (`load`, `decision`, `media_decision`, `records`, `set`, `reset_record`, `reset_space`, `reset_session`); `geolocation.origin`, `notifications.origin`, `notifications.permission_request`, `popups.automatic`, `popups.notice`, `external.url`, `external.local_document`, `external.scheme`, `external.consent`, `authentication.handling`, `authentication.source_label` and `authentication.fixture_trust` |
| Search and translation | `SearchProviderCatalog`; the `CustomSearchEngineAdmission` query; `search.url`, `search.custom_providers` and `translation.*`; the `space.search_provider.*` commands |
| Window state and plans | `window.repair`, `window.split_layout`, `window.tear_off`, `tabs.selection_fallback`, `setup.space`, `setup.tab`, `setup.reconcile`, `onboarding.completion` and `onboarding.guide`; the `workspace.review` query; split-run validation in the workspace import |
| Shortcuts, launch and media | `shortcuts.bindings`, `.assign` and `.numbered_selection`; `launch.plan`; `media.session_event` and `media.arbitrate`; the `tab.open` `after` anchor |
| Behavior preferences | The session's `appPreferences` record behind `preferences.set`, `preferences.translation_rule` and a one-time `preferences.import`. Device-local, never synced |
| Links, Quick Window, presentation | The `ExternalLinkRoute`, `QuickWindowSite` and `BalancedProtectionRules` queries; `links.route_*`, `links.space_removed`, `quick_window.*`, `workspace.command_route`, `page.presentation`, `branding.normalize` and the `space.branding` command |

Selection left the core. The active Space and each Space's shown tab are
window state (`BrowserStoreSelection`, persisted in `BrowserWindowState`).
Commands read the window's `view` and answer a `selection` hint, and
`tab.touch` records only `lastActivatedAt`. Folder depth and count, split
eligibility and cross-Space move eligibility are commands the caller prepares
and releases without committing. `limits` reports every capacity the core
enforces. The `ExternalLinkRoute` query substitutes for a locked Space itself. Link, Quick
Window and authentication-label callers fail closed when the core cannot
answer.

Policy requests are typed on both sides. The core decodes each operation's
request into a record (`*PolicyRequests.cs`) and keeps its codes in `*Codes.cs`
files. Swift names each call with `BrowserSessionOperation`,
`BrowserPolicyOperation` or `BrowserSyncOperation`, sends Codable argument
models, and reads rule failures as `BrowserCoreErrorCode`.

Page commits are owned by the core for selected, Split View and background
pages. Live URL and title observations stay in page presentation, and a
completed navigation sends its URL and document title to the core.

These stay in Swift by design: heraldry vocabulary and composition, favicon
palette extraction, sidebar widgets, Peek motion and presentation phases,
tear-off placement geometry, and default-browser prompt cadence.

Remaining:

- `BrowserStoreSelection.fallbackTabID` picks the first current, pinned and
  saved tab itself before it asks `tabs.selection_fallback`, because the core
  accepts at most three candidates.
- `BrowserSidebarReorderTargetResolver` reads `BrowserCoreLimits` for the
  split member limit instead of asking the core, because it runs on every drag
  frame. The core still rejects anything past the limit.
- Some wire formats stay as they are for compatibility. The core parses
  `TabBatchKind` in PascalCase. Sync document error codes are camelCase while
  session rule codes are snake_case. Identifier casing differs by path: link
  routes use lowercase UUID strings, and other paths use the native encoder's
  spelling.

### WP9. Verification and release gates. Partly done

Done:

- Builds: `Crest`, `CrestChromiumUI`, `CrestChromiumUIProduct` and
  `CrestMobile`; `dotnet test` and `lint-dotnet.sh`; the C ABI harness through
  `Scripts/control-plane/build-experiment.sh`.
- Review packaging for runtime checks:
  `Scripts/control-plane/apply-chromium-host.py`, then
  `build-chromium-baseline.py`, then `package-chromium-host.py` in review mode
  with a throwaway user-data directory. Never launch the unbranded Chromium
  build directly, because its keychain item prompts.
- Product packaging: `.github/workflows/experimental-release.yml` downloads the
  prebuilt engine, packages `CrestChromiumUIProduct` with
  `package-chromium-host.py --product --distribution`, signs it with Crest's
  resolved entitlements and embedded provisioning profile, and notarizes the
  Chromium and WebKit apps and their disk images. The Chromium build is the
  default on `appcast-experimental.xml`. The WebKit build is the alternate on
  `appcast-experimental-webkit.xml`. Never use the review entitlements file for
  the product: it turns on the app sandbox and would strand installed data.
- The Safe Storage keychain item name must not change. A rename rotates the
  encryption key and resets Chromium's tracked preferences.

Remaining:

- The WP0 manual smoke checklist.
- Cross-engine sync convergence between the Chromium Mac product and an iPhone
  WebKit client through the isolated CloudKit review zone, verified from
  records as well as UI.
- The upgrade on a physical device and a sync run against a real account with
  installed Spaces.
- Manual product review of every WP0 to WP7 flow on both engines before early
  user testing.

## Deferred

The product owner has deferred these:

- A Crest color picker for `<input type=color>`. Chromium's own picker is used.
- A Crest popups UI beyond the blocked-popup relay and Site Controls.
- A Crest presentation for JavaScript alerts. Both engines already route
  `alert`, `confirm`, `prompt` and before-unload to `BrowserDialogPresenter`.
- System Picture in Picture on Chromium. Chromium's video PiP uses its own
  Views window. After asking it to enter PiP, Crest reads the page's media
  state to learn the outcome, and no event reports it. The public macOS PiP
  controller takes an `AVPlayerLayer` or `AVSampleBufferDisplayLayer`, so a
  system PiP needs a video-frame bridge from Chromium's video surface, with
  playback control and protected media defined at the adapter. Do not use
  macOS's private PIP framework without a separate product decision.

## Future merge work

The branch stays on the experimental update channel, and no merge is
scheduled. When it does merge, `release.yml` must publish the Chromium product
as the default Mac download with WebKit as the alternate, each with its own
development and stable feeds, and `project.yml`'s default update channel must
move from `experimental` to `development`.

## Ownership decision guide

Use this when a new feature arrives:

1. Must the outcome be identical on WebKit and Chromium, or on Mac and iPhone?
   Then it is a core rule. Make it a session command when it changes durable
   state, or a policy operation when it is a pure answer.
2. Is it rendering, input, scrolling, compositing, an engine handle or a
   platform service? Then it is adapter or platform work behind
   `BrowserPageEngine` or a sibling service protocol. Declare a capability in
   `BrowserEngineRegistration` if an engine may lack it.
3. Is it layout, animation, projection or presentation state? Then it is
   shared Swift, and it gates on capabilities, never on engine `#if` flags.
4. Does it touch a locked Space? The core gate must reject it, and the
   presentation layer must not build its content.
5. Does it open a window? Only from a user action or an explicit extension
   request. Otherwise it reuses the current window or docks inside it.

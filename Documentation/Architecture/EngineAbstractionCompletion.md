# Engine abstraction completion plan

This plan closes the remaining work after the control-plane migration so that
Crest has one finished engine abstraction with two interchangeable adapters,
WebKit and Chromium, and all browser logic in the portable core. It is written
so a new session can execute it without prior context. Read
[ControlPlane.md](ControlPlane.md) first for the ownership contract this plan
completes, and follow `AGENTS.md` for versioning, release notes and tests.

## Goal and principles

Ownership after this plan:

| Layer | Owns | Never owns |
| --- | --- | --- |
| Portable core (`CrestCore`) | Every saved or shared rule that must behave identically on both engines and both platforms: Spaces, tabs, folders, splits, history, archive, sync, access, downloads ledger and risk, credential capture and save policy, site permission records, search providers, setup and import plans, shortcut conflicts, launch policy, app-wide behavior preferences, media-session arbitration | Rendering, input, scrolling, compositing, engine handles, image bytes, platform services |
| Engine adapters (`CrestShared/Infrastructure/WebKit`, `CrestEngines/Chromium`) | Page creation and disposal, loads, navigation history, find, zoom, capture, printing, downloads transport, permission prompts transport, server trust, HTTP auth transport, popups, media observations, user scripts, DevTools, extensions execution | Deciding browser rules; mutating shared state directly |
| Shared Swift (`CrestShared`, `CrestMac`, `CrestMobile`) | Presentation, the viewed Space and selected tab, native windows and cards, projections, platform services (Keychain, CloudKit transport, notifications delivery, LaunchServices) | Engine-specific types or `#if CREST_CHROMIUM_HOST` outside the adapters; second implementations of core rules |

Direct native operations such as scrolling, pointer input, compositing, focus
and page zoom stay inside the adapter and never cross the core boundary. A core
command owns a saved or shared transition; the adapter reports completion.
Choosing which Space or tab a window currently displays is visual Swift state.
Release compositions expose the store's session as a read-only projection.
Sync replacements use the core's checked transaction; the synthetic session
setter exists only in Debug for retained test fixtures.

Product rules that constrain every work package:

- A Space is one profile. No path may share a profile across Spaces or create
  a page, transfer, export or network request for a locked Space without a
  grant. The core gate covers commands, value edits and replacements; the
  presentation layer must not build content for locked Spaces.
- Crest is a single-window app. New windows appear only from user action or an
  explicit extension `windows.create`. Engine surfaces such as DevTools,
  popups and side panels dock inside the Crest window.
- Capability declarations in `BrowserEngineRegistration` must describe the
  adapter's real behavior, and UI must gate on them rather than on build flags.
- Unsupported features have explicit product behavior. Reader, whole-page
  translation and built-in content blocking are unavailable on Chromium by
  decision; selection translation is supported on both engines.

## Current state

The core owns the session spine on every shipping target. The obsolete
`CREST_CORE_BACKED` build flag and its conditional Swift branches are gone.
The Chromium composition is the
installed desktop product with its own engine directory, keychain item,
passkeys through the system sheet, docked DevTools, extensions including side
panels, shortcuts, Space-owned pinned strip and store install. Upgrade from the
WebKit release is verified.

`BrowserPage` (`CrestMac/Infrastructure/Pages`) holds an
`any BrowserPageEngineAdapter` and its `any BrowserPageEngine`; it names no
engine type and has no engine `#if`. The WebKit page adapter
(`BrowserWebKitPageAdapter` plus the page's WebKit delegate and bridge
extensions in `CrestMac/Infrastructure/WebKit`) and the Chromium page adapter
(`ChromiumPageAdapter` in `CrestEngines/Chromium/Apple`) supply the
engine-specific wiring. The composition chooses the engine; no Swift outside
`CrestEngines` asks `CREST_CHROMIUM_HOST`.

The page port now carries Crest-first native context menu actions ahead of
engine and extension items, JavaScript dialogs and before-unload through the
shared dialog presenter, and Chromium Basic and Digest authentication through
the shared per-Space credential session. Each engine registration supplies
its own Feature Flags pane. Chromium's page fullscreen reports presentation
state to the shared shell, which shows the video without browser chrome and
restores the shell on Escape. The page-level PiP lifecycle can request
Chromium's own video PiP when a playing tab leaves view; its floating window
uses Chromium's video surface with a macOS corner snap after a drag.

## Work packages

Each package lists scope, files, design, acceptance and effort. Packages marked
independent can run in parallel in file-disjoint slices. Effort: S under a day,
M a few days, L a week or more.

### WP0. Smoke Chromium-owned surfaces (manual, first)

Chromium routes JavaScript dialogs, before-unload and HTTP Basic/Digest prompts
to Crest's shared presenters. Its file chooser, color picker, notification
delivery and picture-in-picture still use engine surfaces on a real
`chrome::Browser` while the Crest `BrowserWindow` override is inert. Video
fullscreen fills the Crest window and Escape restores the browser shell in an
isolated runtime check. A notification permission grant and successful
`new Notification(...)` call were observed in the isolated app, but macOS
delivery and activation of the source page have not yet been established.

Checklist in a review package: `alert`, `confirm`, `prompt`; `<input type=file>`
single and multiple; a Basic-auth URL; `<input type=color>`; fullscreen video
and Escape; a site notification permission and delivery; PiP button. Record
each as works, wrong window, or missing. Missing items become host hooks in WP2
or WP3. Effort S.

### WP1. Dead-code sweep (partly done)

The dead `CREST_CORE_BACKED` branches and build settings have been removed;
no Swift file still contains that conditional. The original sweep covered
`BrowserSession+Tabs.swift`, `BrowserImportReviewPlan.swift`,
`BrowserSyncJournal.swift`, `BrowserSession.swift`, `BrowserSyncProjection.swift`,
`BrowserSession+Folders.swift`, `BrowserSession+TabBatch.swift`,
`BrowserSyncMergeResolver.swift`, `BrowserStore+Workspaces.swift`,
`BrowserSyncMaterializer.swift`, `BrowserStore+TabOrganization.swift`,
`BrowserSession+FolderBatch.swift`, `BrowserManualSetupPlan.swift`,
`BrowserStore+Spaces.swift`, `BrowserSession+History.swift`,
`BrowserSession+Organization.swift`, `BrowserSession+SplitCopies.swift`.
Keep `BrowserSession+FolderMigration.swift`: its custom Codable path still
loads legacy folder membership and persisted preferences. The unused
`BrowserSession.setFolderColor/Symbol` mutators were removed. Check whether these
other `BrowserSession` mutators still have live callers before removing them: `setTabPinned`,
`setSplitGroupTitle/EmojiIcon/Tint`,
`setSavedTabsExpanded`, `setDefaultSpace`, `moveSpaces`). Move
`BrowserShowcaseSessionFactory` and `BrowserPreviewSessionFactory` behind a
preview-only compilation path. Redirect
`CrestTests/BrowserTabMultiSelectionTests.swift` from `applyTabBatch` to the
command path (`prepareTabBatch`/`commitTabBatch`) or delete cases that only
covered the dead path. Build all schemes and run `CrestCore` tests. Effort M.
Independent; do before WP8 so the live surface is legible.

### WP2. Finish the page port

Goal: `BrowserPage` holds `any BrowserPageEngine` and contains no engine types
or `#if CREST_CHROMIUM_HOST`. Everything WebKit-specific moves into the WebKit
adapter; everything Chromium-specific into `CrestEngines/Chromium/Apple`.

2a. User-script and message channel (do first; unlocks 2c to 2h, WP4, WP5).
Add to the engine port: `addUserScript(source, world, injectionTime, mainFrameOnly)`
and `setScriptMessageHandler(name, handler)` per page. WebKit implements them
with `WKUserContentController`; Chromium implements them in
`crest_chrome_host.mm` with a `WebContentsObserver` injecting into an isolated
world at document start and a message channel back to Swift (the Web Store
injection in the host is the pattern). Then install Crest's existing content
bridges through the port instead of the WebKit initializer arm: credentials,
link hover, link context, blocked popups, media session, user activity,
visited-link styling, geolocation, hosted notifications. Effort L once.

2b. Split `BrowserPage`. Done. The page and its engine-neutral extensions
live in `CrestMac/Infrastructure/Pages` and the shared page logic in
`CrestShared/Infrastructure/Pages`. The pool builds each page's adapter through
an injected `BrowserPageEngineMaker` (nil builds WebKit from the pool's own
configuration); `BrowserPage.init(engine:)` takes the adapter, and a WebKit
convenience initializer keeps `configuration:` callers. The adapter owns the
engine-built controllers (link hover and drag, Picture in Picture, reader,
favicons, media capture, content rules, focus restoration, user activity,
visited links) and wires delegates, bridges and observers in `attach(to:)`.
The engine reports through typed `BrowserPageEngineEvent`s (granular WebKit
observations or a `BrowserPageEngineState` snapshot) and
`BrowserEngineLinkAction`s. The port gained `currentURL`, `canGoBack`,
`canGoForward`, `reportsNavigationState`, `synchronizeHistory()`,
`evaluateInMainFrame(_:)` and `clearSiteData(for:)`; WebKit applies automatic
popups through the port too. Back and forward menus read
`pageEngine.backHistory/forwardHistory` on both engines, and the failure
notice's Back leaves a Chromium error page through history. WebKit bridges
that sat in shared infrastructure folders (content blocking, geolocation,
hosted notifications, media session bridge, reader, whole-page translation,
popups, user activity, website data, WebKit downloads) now live under
`CrestShared/Infrastructure/WebKit` or `CrestMac/Infrastructure/WebKit`, and the
engine-neutral pool, host view, tab-state and reconciliation types moved out
of the WebKit folders into `Infrastructure/Pages`. `BrowserPagePool` is
engine-neutral; its WebKit hosting (configurations, private website data
stores, content rules, WebKit popup adoption, `WKScriptMessage` routing) is
`BrowserPagePool+WebKit.swift`. `BrowserDownloadCenter` keeps the ledger,
feedback, data saves and engine-reported transfers; `WKDownload`s run through
`BrowserWebKitDownloadTransport`, one `BrowserDownloadTransport`. Media Session
keeps one coordinator over `BrowserMediaSessionTransport`, with the WebKit
transport in the WebKit folder. Shared code that still names WebKit: the
credential bridge's WebKit installer (`CredentialContentBridge.swift`), the
page's `BrowserPopupCoordinator`, `BrowserTransientPageLease`'s content rules
and the pool's WebKit service defaults. Mobile keeps `MobileBrowserPage`
concretely typed.

2c. Small port gaps, all S unless noted:
- Per-Space default zoom applied above the engine fork; Chromium replays zoom
  on `created`.
- `BrowserDownloadCenter.resetAutomaticDownloadSequence(for:)` takes the page
  engine (done); the page calls it on detach for both engines.
- Quick Window user-activity monitoring through the channel (2a) so the idle
  timer sees typing.
- Viewport-fit: removed, not ported. Its only caller zoomed a page with an
  authored CSS minimum width down to the space a WebKit extension side-panel
  card left in the row; that card was retired with WebKit extensions.
  Split cards and Peek reflow at the page's own zoom, and the developer
  toolbar's device widths use `developerViewport`, which never went through
  it. Chromium side panels narrow the page the way Chrome's do.
- Find: done. Both engines always wrap, which is all Crest's find asks for,
  so the configuration carries no wrap option. Chromium's host reports the
  total and the selected ordinal from `FindTabHelper`'s final update and
  the find bar shows "n of m"; WebKit's public find reports only whether a
  match exists, which the WebKit registration declares as a limitation.
- Focus restoration: verify end to end on Chromium; add `focusPage` if needed.
- Favicon manual refresh and archived-tab icon pull; `themeColor` in the
  `changed` payload for tab accents.
- Side panel host for Quick Window and setup windows, or route requests to
  the requesting page's window.

2d. Popups: relay Chromium's blocked-popup observations
(`blocked_content::PopupBlockerTabHelper`) as a `popup_blocked` engine event
with origin and count, plus a host command to allow popups for an origin via
the existing content-settings path. Then declare `popups` supported and remove
the `unverified` limitation. Effort M.

2e. Media: host events for media session metadata and transport, and a PiP
toggle command with a `picture_in_picture` event, feeding
`BrowserMediaSessionStore` and the PiP controller through the port. Chromium's
video PiP currently embeds a Viz surface in a Views overlay window. On macOS,
the public system PiP controller takes an `AVPlayerLayer` or
`AVSampleBufferDisplayLayer`; it cannot adopt that Viz surface directly. A
system PiP implementation therefore needs a real video-frame bridge, with
playback control and protected-media behavior defined at the engine adapter.
An isolated macOS probe confirmed that public AVKit presents a live
`AVSampleBufferDisplayLayer` in the system Picture in Picture window. The
unresolved part is supplying that layer with Chromium's video surface frames
at playback rate, without capturing page chrome or requiring Screen Recording.
Validate it with clear and protected video, multiple displays and full-screen
Spaces, plus hands-on dragging and resizing. A window-style change alone does
not satisfy PiP parity. Do not use macOS's private PIP framework without a
separate product decision. Effort L.

2f. Link hover through 2a or a native `link_hovered` event. Effort M.

2g. Visited-link styling from Crest history through 2a. Effort S.

2h. Host commands port for the Chromium root. Done. `BrowserEngineHostCommands`
(`CrestShared/Infrastructure/Engines`) is implemented by `BrowserMacApplication`
with the same store, page and window operations the WebKit menus, Settings
presentation and external-link handler run: extension and external tabs,
Settings, Getting Started, Extensions settings, Space selection (window state),
quit persistence flush and private-browsing close. `CrestChromiumRoot` and
`ChromiumNativePage` no longer mutate `BrowserStore`; the page receives the port
at creation. Engine-created page adoption is the pool's typed
`adoptEnginePage(_:)`. Still static: the Chromium extension store and side-panel
routing reach `CrestChromiumRoot.engineHost`, `extensions` and
`activeNativeWindow`, which are engine-host lookups rather than store edits.

Acceptance for WP2: zero `#if CREST_CHROMIUM_HOST` outside `CrestEngines`
(met: the composition now selects its entry point, engine registration and
engine-contributed views by file in `project.yml`, and injects the page
engine, Site Controls anchor, icon defaults domain and review store); zero
`webKitView` reads outside the WebKit adapter (met; the pool's WebKit hosting
is now its own WebKit extension); back-forward menus, hover URL, blocked-popup
notice, media controls and Quick Window activity work on Chromium; both
`Crest` and `CrestChromiumUI` build; retained behavioral tests pass.

### WP3. Security indicator, certificates and HTTP auth

- Security state: done. Each page carries an engine-neutral
  `BrowserPageSecurityState` (`none`, `insecure`, `secure`, `mixed_content`,
  `certificate_error`, `dangerous`). Chromium reports it in every `changed`
  payload as `security`, from `SecurityStateTabHelper`'s level and visible
  security state (malicious content, certificate status, mixed or
  cert-error subresources). WebKit derives it from the scheme,
  `hasOnlySecureContent`, the trust result WebKit left on `serverTrust`, and
  whether the person accepted that certificate through
  `BrowserServerTrustOverrideStore`. Site Controls shows each state, keeps
  `View Certificate` for any page whose engine hands over its trust, and
  says "Connection Details Unavailable" rather than "Secure" when an HTTPS
  page has no trust to show.
- Certificate errors on Chromium stay on Chromium's own interstitial, which
  explains the error and offers to proceed; that decision belongs to the
  engine profile rather than `BrowserServerTrustOverrideStore`, and the
  Chromium registration declares it. Moving it into Crest, with the override
  recorded by the core (WP8, permissions aggregate), remains open.
- HTTP auth: done for Basic and Digest. The host's
  `setHTTPAuthenticationHandler(page:handler:)` defers its reply to the shared
  `BrowserHTTPAuthenticationSession` and prompt on both engines; proxy
  challenges and other schemes keep the engine's own handling.

Acceptance: a mixed-content page shows the mixed state; a certificate error
shows its state and can be proceeded past (Crest's store on WebKit,
Chromium's interstitial on Chromium); a Basic-auth site is reachable with
Crest's prompt; `View Certificate` works. Remaining: Crest-owned
proceed-anyway on Chromium. Effort M for the remainder.

### WP4. Credentials on Chromium

Through 2a, install the credential content bridge and reuse
`BrowserCredentialFormMessage` verbatim. `fillCredential` and
`fillGeneratedPassword` execute through the engine port (WebKit
`evaluateJavaScript` in the bridge world; Chromium isolated-world execution).
Save-candidate detection, update-versus-new and recency rules move to the core
(WP8). Chromium's own password manager is turned off for every page the host
creates or adopts, in Space and private profiles alike (a private profile and
its original profile both), whether or not a credential bridge is installed,
so its save and fill bubbles never appear. iCloud Passwords via the extension
and passkeys via the system sheet stay as they are.

Acceptance: fill, save prompt, update prompt and generated password work on a
test login page in both engines with the same outcomes; no Chromium password
bubble appears. Effort M after 2a.

### WP5. Site permissions, geolocation, notifications

- One source of truth. Permission decisions are core records (WP8). WebKit
  applies them through Crest's prompts as today; Chromium applies them through
  `HostContentSettingsMap` and reports engine prompts through its permission
  handler with a typed `BrowserEnginePermissionResponse`, so Crest's prompt UI
  and the Privacy pane list work identically on both engines. Remove the inert
  Privacy list state on Chromium.
- Live application (done). Each open page owns one engine-neutral
  `BrowserPageSitePermissionSession`, a synchronous observer of
  `BrowserSitePermissionCenter`. A change from a prompt, Site Controls or the
  Privacy pane that affects the page's site is applied at once through
  `BrowserPageEngine.applySitePermission` (Chromium content settings), and a
  withdrawn camera or microphone grant ends capture through
  `stopMediaCapture` (WebKit capture state). The adapter's
  `sitePermissionDidChange` refreshes bridges Crest runs in the page (WebKit
  hosted notifications); WebKit geolocation observes the centre itself.
- Geolocation and hosted web notifications: WebKit keeps its bridges and
  coordinators in the WebKit folder. Chromium uses the engine's own location
  and notification implementations under Crest's decision; Crest's
  `UserNotifications` delivery, source-tab activation and withdrawal of
  delivered notifications need a host notification hook, and stopping live
  capture or location directly needs a host command. Both are declared
  limitations of the Chromium registration.
- Clear site data and reload: route to the engine (`WKWebsiteDataStore`
  removal for the origin on WebKit; browsing-data remover on Chromium) or hide
  when unsupported.

Acceptance: camera, microphone, location and notifications prompt once, are
remembered per site and Space, appear in Privacy, and can be revoked there on
both engines. Effort L.

### WP6. Capability truth and UI hygiene

- Filter `BrowserCommandActions.paletteCommands` and
  `BrowserShortcutCommand.userFacingCases` by capability so Reader, Content
  Blocking and Translation do not appear on an engine that lacks them.
- Gate the Feature Flags destination on the engine that owns the flag catalog
  (`isProvidedByCurrentEngine`).
- Privacy pane: when content blocking is unavailable, show one sentence
  explaining that blocking comes from extensions on this engine.
- Archive format: decide whether Crest reads the other engine's archive format
  (`.webarchive` on Chromium, `.mhtml` on WebKit). If not, the Open File panel
  already offers only the engine's format; document it in Help.
- `BrowserCorePolicy.allowsInternalPages` uses the `internal-pages` capability
  instead of `#if`.
- Wire or delete the declared capabilities with no `supports` call sites so the
  registration is a contract, not documentation.

Effort M. Independent.

### WP7. WebKit symmetry (done)

`BrowserWebKitPageEngine` reports its real PiP activity for residency, stages
Peek navigation with the source request and website data store, and prepares a
page close through WebKit's before-unload path. The staged request carries the
URL and referrer; WebKit does not expose the initiating frame's full security
context to a second page. The registration declares that limit and the desktop
before-unload SPI dependency.

### WP8. Core extraction of the remaining rule aggregates

Each aggregate becomes core domain and application types with focused tests,
exposed either as semantic session commands, `crest_core_evaluate_policy`
operations, or new bounded exports, following the C# library style rules in
`CrestCore` (regions, centralized codes, `Scripts/control-plane/lint-dotnet.sh`).
Swift keeps projections and adapters only.

| Aggregate | Swift today | Core target | Effort |
| --- | --- | --- | --- |
| Downloads (done: `crest_downloads_*` ledger; `downloads.progress`, `downloads.risk`, `downloads.automatic` ops) | `BrowserDownloadLedger`, `BrowserDownloadProgressPolicy`, `BrowserAutomaticDownloadPolicy`, risk assessment | Download ledger aggregate with state machine, ordering, acknowledgement, expiry; progress and ETA policy op; automatic-download risk op. Engines report events; Swift renders | L |
| Credentials and passkeys (done: `credentials.capture`, `.fill`, `.save_validity`, `.save_match`, `.save_plan`, `.most_recent`, `.password_recipe`, `.system_write_through`, `.system_write_through_offer` and `passkeys.access_status` ops; passwords never cross) | `BrowserCredentialCapturePolicy`, save plan and disposition, recency, `BrowserStrongPasswordGenerator`, passkey access and write-through policies | Capture and save decision op (form message in, disposition out); generator op; passkey write-through policy. Vault storage stays native | M |
| Site permissions and origins (done: `crest_permissions_*` ledger with `load`, `decision`, `media_decision`, `records`, `set`, `reset_record`, `reset_space`, `reset_session`; `geolocation.origin`, `notifications.origin`, `notifications.permission_request`, `popups.automatic`, `popups.notice`, `external.url`, `external.local_document`, `external.scheme`, `external.consent`, `authentication.handling`, `authentication.source_label`, `authentication.fixture_trust` ops; saved document keeps its format and key, not synced) | `BrowserSitePermission*` policies, blocked-popup notice, geolocation origin policy, hosted notification policies, authentication policies, external scheme and URL policies, local-file policy | Per-Space permission records in the session with persistence and sync rules; origin and scheme policy ops. Adapters transport prompts | L |
| Search and browsing preferences (done: `SearchProviderCatalog`; `search.url`, `search.custom_provider`, `search.custom_providers`, `translation.*` ops; `space.search_provider.*` commands) | `BrowserSearchProvider` catalog and URL templates, custom-provider upsert and removal, `BrowserAutomaticTranslationRules` | Provider catalog and query construction in the core (`SearchProvider` currently only an enum); custom-provider commands; translation rules op | M |
| Window state and plans (done: `window.repair`, `window.split_layout`, `window.tear_off`, `tabs.selection_fallback`, `setup.space`, `setup.tab`, `setup.reconcile`, `onboarding.completion` and `onboarding.guide` ops; `workspace.review` query; split-run validation in the workspace import) | `BrowserWindowState.repair`, `repairSplitLayout`, `ensureTabSelection`, `captureSplitLayout`; `BrowserManualSetupPlan`; `BrowserImportReviewPlan`; onboarding completion | Window-state repair op (core `WindowState` is a bare record today); setup and import-review plan operations extending `WorkspaceImportPolicy`; onboarding completion rule | L |
| Shortcuts, launch, media (done: `shortcuts.bindings`, `.assign`, `.numbered_selection`, `launch.plan`, `media.session_event` and `media.arbitrate` ops; `tab.open` `after` anchor) | Shortcut conflict and numbered selection policies; `BrowserLaunchIsolationPolicy`, startup behavior, tab insertion; `BrowserMediaSessionStore` arbitration | Conflict and selection ops; launch and startup policy op; media-session ownership and eviction op. Section and search grouping stay in Swift | M |
| Behavior preferences (done: session `appPreferences` record behind `preferences.set`, `preferences.translation_rule` and a one-time `preferences.import` of the legacy defaults; the session's `launch.plan` read applies the saved startup choice; device-local, never synced) | Startup behavior, page translation offer/automatic/rules, WebKit spell checking, automatic Picture in Picture, saved-tab close policy and favicon return, Split View focus-follows-mouse in `@AppStorage` and small defaults stores | Core-owned record persisted with the session checkpoint; `BrowserAppPreferenceStore` is the Swift projection. Appearance preferences, link preferences, shortcut overrides, sync and download settings stay native | M |

Stragglers, all folded in. `BrowserSession.ensureSelection` and
`repairRuntimeIntegrity`, `BrowserSplitGroupNormalizer`,
`normalizeSplitGroupsAfterUserMutation` and tear-off eligibility in
`BrowserMacWindowCoordinator` went with the window-state aggregate
(`window.*`, `tabs.selection_fallback`). The borrowed-workspace settings
fan-out is one core routing rule (`workspace.command_route`, enforced by the
borrowed authority's Space commands); `BrowserLinkPreferenceStore` route edits,
the Space-deletion cascade and `BrowserLinkRoutingPolicy` are `links.*`
operations; Quick Window archive and retargeting are `quick_window.*`
operations; `BrowserPagePresentationPolicy`, Balanced content-blocking
composition and branding normalization are `page.presentation`,
`content_blocking.rules` and `branding.normalize`, and the `space.branding`
command applies the same branding rules.

Stays in Swift by design: heraldry vocabulary and composition, favicon palette
extraction, sidebar widgets, Peek motion and presentation phases, tear-off
placement geometry, default-browser prompt cadence.

Page commit ownership is complete for selected, Split View and background pages.
Live URL and title observations stay in page presentation; a completed
navigation sends its URL and document title to the core. WebKit reads the
finished document title before publishing completion, and Chromium publishes
completion only for a committed navigation. Late favicons still update the
matching saved tab, while address submission can convert a native tab into a
web tab before loading.

Acceptance: `Documentation/Architecture/ControlPlane.md` step 1 acceptance
("no parallel domain implementation") becomes literally true; a grep for
`session.` mutations outside `applyCoreEdit` and command paths returns nothing
live; core tests cover each aggregate's edge cases.

### WP9. Verification and release gates

- Builds: `Crest`, `CrestChromiumUI`, `CrestChromiumUIProduct`, `CrestMobile`;
  `dotnet test` and `lint-dotnet.sh`; the C ABI harness via
  `Scripts/control-plane/build-experiment.sh`.
- Review packaging for runtime checks: `Scripts/control-plane/apply-chromium-host.py`
  then `build-chromium-baseline.py`, then `package-chromium-host.py` in review
  mode with a throwaway user-data directory and `--use-mock-keychain`. Never
  launch the unbranded Chromium build directly; its keychain item prompts.
- Product packaging: `package-chromium-host.py --product` with
  `CrestChromiumUIProduct`, the Mac target's resolved entitlements and embedded
  provisioning profile, signed with the identity the profile authorizes
  (Developer ID). Never use the review entitlements file for the product; it
  enables the app sandbox and would strand installed data.
- Safe-storage keychain item name must not change outside the adoption step;
  a rename resets Chromium's tracked preferences.
- Cross-engine sync convergence with an iPhone WebKit client through the
  isolated CloudKit review zone, verified from records and UI.
- Manual product review of every WP0 to WP7 flow on both engines before early
  user testing.

## Ownership decision guide

Use this when a new feature arrives:

1. Does the outcome need to be identical on WebKit and Chromium, or on Mac and
   iPhone? Then the decision is a core rule. Expose it as a session command
   when it changes durable state, or a policy operation when it is a pure
   answer.
2. Is it rendering, input, scrolling, compositing, an engine handle, or a
   platform service? Then it is adapter or platform work behind a port on
   `BrowserPageEngine` or a sibling service protocol, with a capability
   declared in `BrowserEngineRegistration` if an engine may lack it.
3. Is it layout, animation, projection or presentation state? Then it is
   shared Swift, and it must gate on capabilities, never on `#if` engine flags.
4. Does it involve a locked Space? The core gate must reject it, and the
   presentation layer must not build its content.
5. Does it open a window? Only from a user action or an explicit extension
   request; otherwise it reuses the current window or docks inside it.

## Suggested order and parallelization

1. WP0 and WP1 immediately, in parallel; WP1 is mechanical.
2. WP2a, then WP2b to 2h, WP4 and WP5 in file-disjoint slices; WP3 in
   parallel since it is host-hook work.
3. WP6 and WP7 in parallel with 2, both small and independent.
4. WP8 aggregates in parallel with everything above; downloads and
   credentials first because WP4 and WP5 consume them.
5. WP9 gates before early user testing.

## Definition of done

- One `BrowserPage` typed over the engine port; adapters contain all
  engine-specific code; no engine `#if` or engine types outside adapters.
- Every capability declared is queried somewhere and matches adapter behavior.
- No live Swift decides a browser rule that the core also decides; the dead
  branches are gone.
- Every gap in the parity table above is either implemented on both engines
  or declared unavailable with explicit product behavior.
- The locked-Space, single-profile and single-window rules hold on every path
  listed here, verified by tests at the owning layer.
- Both engines pass the manual flow review; the product package installs over
  an existing session without loss.

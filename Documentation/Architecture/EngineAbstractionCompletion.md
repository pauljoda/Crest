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
| Portable core (`CrestCore`) | Every rule that must behave identically on both engines and both platforms: session, Spaces, tabs, folders, splits, history, archive, sync, access, downloads ledger and risk, credential capture and save policy, site permission records, search providers, window-state repair, setup and import plans, shortcut conflicts, launch policy, media-session arbitration | Rendering, input, scrolling, compositing, engine handles, image bytes, platform services |
| Engine adapters (`CrestShared/Infrastructure/WebKit`, `CrestEngines/Chromium`) | Page creation and disposal, loads, navigation history, find, zoom, capture, printing, downloads transport, permission prompts transport, server trust, HTTP auth transport, popups, media observations, user scripts, DevTools, extensions execution | Deciding browser rules; mutating shared state directly |
| Shared Swift (`CrestShared`, `CrestMac`, `CrestMobile`) | Presentation, projections, native window and card hosting, platform services (Keychain, CloudKit transport, notifications delivery, LaunchServices) | Engine-specific types or `#if CREST_CHROMIUM_HOST` outside the adapters; second implementations of core rules |

Direct native operations such as scrolling, pointer input, compositing, focus
and page zoom stay inside the adapter and never cross the core boundary. A core
command owns the semantic transition; the adapter reports completion.

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

The core owns the session spine on every shipping target; `CREST_CORE_BACKED`
is defined for all of them, so every `#if !CREST_CORE_BACKED` branch and every
`#else` arm of `#if CREST_CORE_BACKED` is dead. The Chromium composition is the
installed desktop product with its own engine directory, keychain item,
passkeys through the system sheet, docked DevTools, extensions including side
panels, shortcuts, Space-owned pinned strip and store install. Upgrade from the
WebKit release is verified.

The largest remaining fork is `CrestMac/Infrastructure/WebKit/BrowserPage.swift`.
Under `CREST_CHROMIUM_HOST` its `webView` is nil, so every
`guard let webView = webKitView` site (19 across 8 files) silently no-ops, and
the WebKit initializer arm that installs Crest's in-page bridges never runs.
This one fork explains most user-visible gaps on Chromium.

## Work packages

Each package lists scope, files, design, acceptance and effort. Packages marked
independent can run in parallel in file-disjoint slices. Effort: S under a day,
M a few days, L a week or more.

### WP0. Smoke Chromium-owned surfaces (manual, first)

Chromium supplies JavaScript dialogs, the file chooser, HTTP auth prompts,
color picker, fullscreen, notification delivery and picture-in-picture through
its `WebContentsDelegate` on a real `chrome::Browser` while the Crest
`BrowserWindow` override is inert. Any of these anchored to a Views browser
view may fail silently.

Checklist in a review package: `alert`, `confirm`, `prompt`; `<input type=file>`
single and multiple; a Basic-auth URL; `<input type=color>`; fullscreen video
and Escape; a site notification permission and delivery; PiP button. Record
each as works, wrong window, or missing. Missing items become host hooks in WP2
or WP3. Effort S.

### WP1. Dead-code sweep

Delete every `#if !CREST_CORE_BACKED` block and every `#else` arm of
`#if CREST_CORE_BACKED`, then remove the now-unconditional `#if`. Files with the
most dead lines: `BrowserSession+Tabs.swift`, `BrowserImportReviewPlan.swift`,
`BrowserSyncJournal.swift`, `BrowserSession.swift`, `BrowserSyncProjection.swift`,
`BrowserSession+Folders.swift`, `BrowserSession+TabBatch.swift`,
`BrowserSyncMergeResolver.swift`, `BrowserStore+Workspaces.swift`,
`BrowserSyncMaterializer.swift`, `BrowserStore+TabOrganization.swift`,
`BrowserSession+FolderBatch.swift`, `BrowserManualSetupPlan.swift`,
`BrowserStore+Spaces.swift`, `BrowserSession+History.swift`,
`BrowserSession+Organization.swift`, `BrowserSession+SplitCopies.swift`.
Delete `BrowserSession+FolderMigration.swift` (entirely dead) and the
`BrowserSession` mutators with no live callers after the sweep (`setTabPinned`,
`setSplitGroupTitle/EmojiIcon/Tint`, `setFolderColor/Symbol`,
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

2b. Split `BrowserPage`. Move `BrowserPage.swift` lines that construct
WebKit-only controllers into a `BrowserWebKitPageEngine` extension or a
WebKit page adapter; replace `webKitView` reads (19 sites across 8 files:
`PlatformPage+Navigation`, `+ContentPolicy`, `+BlockedPopups`, `+Geolocation`,
`+MediaSessions`, `+Residency`, `BrowserPage+ViewportFit`,
`BrowserPage+NativePresentation`, `BrowserPage+WKNavigationDelegate`) with
engine-port calls. Remove the `navigationHistory` discard stub at
`BrowserPage.swift` and bridge `pageEngine.backHistory/forwardHistory` into it
so back and forward long-press menus work on Chromium. Remove the
`(webView as? BrowserDesktopWebView)` back-references. Mobile: `MobileBrowserPage`
already types its engine concretely; keep it protocol-typed where shared code
requires. Effort L.

2c. Small port gaps, all S unless noted:
- Per-Space default zoom applied above the engine fork; Chromium replays zoom
  on `created`.
- `BrowserDownloadCenter.resetAutomaticDownloadSequence` gets an engine-neutral
  hook.
- Quick Window user-activity monitoring through the channel (2a) so the idle
  timer sees typing.
- Viewport-fit: host command `engine.viewport_fit(width)`; applies to split
  cards, Peek and the developer toolbar device widths (M).
- Find: add `wraps` to the host selector and return active and total match
  counts (M).
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
`BrowserMediaSessionStore` and the PiP controller through the port. Effort L.

2f. Link hover through 2a or a native `link_hovered` event. Effort M.

2g. Visited-link styling from Crest history through 2a. Effort S.

2h. Host commands port for the Chromium root: replace the direct `BrowserStore`
mutations in `CrestChromiumRoot` (Space select, new tab, page select, settings,
sync flush, private window close) and the `ChromiumNativePage` reach into
`CrestChromiumRoot.extensionSpaces` with a `BrowserEngineHostCommands` port
owned by the shared layer and implemented by the composition. Effort L.

Acceptance for WP2: zero `#if CREST_CHROMIUM_HOST` outside `CrestEngines`
(currently 24 across 11 files, 10 in `BrowserPage.swift`); zero `webKitView`
reads outside the WebKit adapter; back-forward menus, hover URL, blocked-popup
notice, media controls and Quick Window activity work on Chromium; both
`Crest` and `CrestChromiumUI` build; retained behavioral tests pass.

### WP3. Security indicator, certificates and HTTP auth

- Server trust: host method returning the page's `SecTrust` and a `security_state`
  event carrying secure, mixed-content and certificate-error states. Replace
  `hasOnlySecureContent = scheme == "https"` with the engine's state on both
  adapters. Restore the certificate sheet and the certificate-error
  proceed-anyway flow through `BrowserServerTrustOverrideStore`, with the
  override decision recorded by the core (WP8, permissions aggregate).
- HTTP auth: host hook `setAuthenticationHandler(page, handler)` with a
  deferred reply (the modified-link handler is the shape). Drive the existing
  `BrowserHTTPAuthenticationSession`, including saved HTTP credentials from the
  vault, on both engines.
- Downgrade gracefully: if the host cannot supply trust for a page, show
  "connection details unavailable" rather than "Secure".

Acceptance: a mixed-content page shows the mixed state; a self-signed site
offers proceed-anyway and remembers it per the store; a Basic-auth site is
reachable with Crest's prompt; `View Certificate` works. Effort L.

### WP4. Credentials on Chromium

Through 2a, install the credential content bridge and reuse
`BrowserCredentialFormMessage` verbatim. `fillCredential` and
`fillGeneratedPassword` execute through the engine port (WebKit
`evaluateJavaScript` in the bridge world; Chromium isolated-world execution).
Save-candidate detection, update-versus-new and recency rules move to the core
(WP8). Chromium's own password bubbles remain suppressed. iCloud Passwords via
the extension and passkeys via the system sheet stay as they are.

Acceptance: fill, save prompt, update prompt and generated password work on a
test login page in both engines with the same outcomes; no Chromium password
bubble appears. Effort M after 2a.

### WP5. Site permissions, geolocation, notifications

- One source of truth. Permission decisions are core records (WP8). WebKit
  applies them through Crest's prompts as today; Chromium applies them through
  `HostContentSettingsMap` and reports engine prompts as
  `permission_requested` events with a reply, so Crest's prompt UI and the
  Privacy pane list work identically on both engines. Remove the inert
  Privacy list state on Chromium.
- Geolocation and hosted web notifications: through 2a and the permission
  event, reuse the existing coordinators and `UserNotifications` delivery.
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

### WP7. WebKit symmetry

Three places where WebKit is behind Chromium:
- `hasPictureInPicture` is hardcoded false in `BrowserWebKitPageEngine`;
  report the real value so residency can evict a PiP page.
- `stageNavigation` is unimplemented on WebKit, so Peek from a modified link
  loses the initiating frame's referrer and security context; implement a
  staged navigation token on WebKit.
- Declare and implement `before-unload` on WebKit through the close preparer,
  so a dirty page prompts before closing as it does on Chromium.

Effort M. Independent.

### WP8. Core extraction of the remaining rule aggregates

Each aggregate becomes core domain and application types with focused tests,
exposed either as semantic session commands, `crest_core_evaluate_policy`
operations, or new bounded exports, following the C# library style rules in
`CrestCore` (regions, centralized codes, `Scripts/control-plane/lint-dotnet.sh`).
Swift keeps projections and adapters only.

| Aggregate | Swift today | Core target | Effort |
| --- | --- | --- | --- |
| Downloads (done: `crest_downloads_*` ledger; `downloads.progress`, `downloads.risk`, `downloads.automatic` ops) | `BrowserDownloadLedger`, `BrowserDownloadProgressPolicy`, `BrowserAutomaticDownloadPolicy`, risk assessment | Download ledger aggregate with state machine, ordering, acknowledgement, expiry; progress and ETA policy op; automatic-download risk op. Engines report events; Swift renders | L |
| Credentials and passkeys | `BrowserCredentialCapturePolicy`, save plan and disposition, recency, `BrowserStrongPasswordGenerator`, passkey access and write-through policies | Capture and save decision op (form message in, disposition out); generator op; passkey write-through policy. Vault storage stays native | M |
| Site permissions and origins | `BrowserSitePermission*` policies, blocked-popup notice, geolocation origin policy, hosted notification policies, authentication policies, external scheme and URL policies, local-file policy | Per-Space permission records in the session with persistence and sync rules; origin and scheme policy ops. Adapters transport prompts | L |
| Search and browsing preferences | `BrowserSearchProvider` catalog and URL templates, custom-provider upsert and removal, `BrowserAutomaticTranslationRules` | Provider catalog and query construction in the core (`SearchProvider` currently only an enum); custom-provider commands; translation rules op | M |
| Window state and plans | `BrowserWindowState.repair`, `repairSplitLayout`, `ensureTabSelection`, `captureSplitLayout`; `BrowserManualSetupPlan`; `BrowserImportReviewPlan`; onboarding completion | Window-state repair op (core `WindowState` is a bare record today); setup and import-review plan operations extending `WorkspaceImportPolicy`; onboarding completion rule | L |
| Shortcuts, launch, media | Shortcut conflict and numbered selection policies; `BrowserLaunchIsolationPolicy`, startup behavior, tab insertion; `BrowserMediaSessionStore` arbitration | Conflict and selection ops; launch and startup policy op; media-session ownership and eviction op. Section and search grouping stay in Swift | M |

Stragglers to fold in: `BrowserSession.ensureSelection` and
`repairRuntimeIntegrity` (already delegate to core repair; remove the Swift
copies), the borrowed-workspace settings fan-out repeated at eight call sites
in `BrowserStore+Spaces`, `+Credentials`, `+Workspaces` (one core routing rule
via the borrowing authority), `BrowserSplitGroupNormalizer` and
`normalizeSplitGroupsAfterUserMutation` (core split policy already exists),
`BrowserLinkPreferenceStore` route mutations and the Space-deletion cascade,
Quick Window archive and retargeting policies, `BrowserPagePresentationPolicy`,
`BrowserContentBlockingRules` composition, tear-off eligibility in
`BrowserMacWindowCoordinator`, `BrowserSpaceBranding.normalized()`.

Stays in Swift by design: heraldry vocabulary and composition, favicon palette
extraction, sidebar widgets, Peek motion and presentation phases, tear-off
placement geometry, default-browser prompt cadence.

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

# Crest architecture

Crest is a native SwiftUI browser for Apple silicon. It uses WebKit as the browsing engine and treats a **Space** as the primary privacy and organization boundary.

## Source map

```text
CrestShared/
  Application/       Cross-platform coordination and stores
  DesignSystem/      Tokens, reusable components, and modifiers
  Domain/            Value types, policies, and state transitions
  Features/          Shared feature presentation by user purpose
  Infrastructure/    Persistence, WebKit policy, Keychain, and sync
  Resources/         Localizations, privacy manifest, and app icon
CrestMac/             macOS app, WebKit host, commands, and presentation
CrestMobile/          iPhone/iPad app, adaptive chrome, and WebKit host
```

`project.yml` is the target and build-setting source of truth. XcodeGen produces `Crest.xcodeproj`.

## Space isolation

Every persistent Space owns its own browsing state. A Space boundary includes:

- WebKit website data store, cookies, cache, and sessions
- tabs, pinned sites, folders, history, archive, and appearance
- Crest Passwords and credential matching
- content-blocking, permission, and extension state
- synchronization records and deletion tombstones

Private Spaces use non-persistent WebKit storage and do not join normal persistence or sync. Quick Window and Peek are transient presentations, but deliberately borrow the selected Space's session boundary when a signed-in preview is useful.

Space deletion is coordinated across browser state, website data, credentials, sync records, and window restoration. A stale synced record must not resurrect a deleted Space.

## Data and synchronization

Local state is durable first. CloudKit synchronizes portable Space, tab, history, and preference records while secrets remain in the Keychain. Ordered collections use fractional positions so independent devices can insert and reorder without renumbering every record. Merge behavior is deterministic, and deletion wins through tombstones.

Crest can import browser bookmarks and sessions, and its portable archive format keeps migration separate from live CloudKit records. Archive readers validate identifiers and relationships before applying imported state.

Import adapters share URL and whitespace sanitation while retaining their own title limits, fallback rules, and errors. Arc bookmark and session imports read one typed source document and apply separate placement and traversal policies. Related background-page metadata and completed visits publish together, using one combined persistence scope.

## Windows on macOS

**New Window** opens another view of the same browsing workspace. `BrowserStoreFamily` owns one observable session; each `BrowserStore` retains only its window's selections and projects them over that session. Changes are visible across windows before persistence. Mutations run on the main actor, and family revisions reject stale background sync work. A restored window keeps its own Space and tab selections, including an intentionally empty selection.

Normal windows share a `BrowserPageRuntimeStore`. Each tab has one `BrowserTabRuntime` owning its live WebKit view, suspended configurations, and history. The focused window hosts the live view; other windows showing the same tab use its preview and can take over presentation. Native tab models share the same workspace lifetime. Closing a normal window releases its presentation while retaining shared tabs and their loaded state.

**Blank Window** creates a temporary workspace with no initial tabs. It borrows the source Space's website profile, credentials, permissions, identity, and settings. Its tabs, pins, folders, history, archive, favicons, and tab-state storage remain local and in memory, with no sync coordinator or window restoration. Settings edit the canonical source profile through a separate selection facade. Source policy changes apply immediately; removing or replacing the source profile ends the temporary workspace. Closing it discards its local browsing records.

Dragging one tab between workspaces moves its existing identity and runtime, including native content models and retained navigation state. The destination receives a Current tab without source folder or split membership, and the transfer does not archive the source tab. An empty source window stays open. A tear-off prepares a destination first and commits only after the native window attaches and both model and runtime assignments pass validation. Cancellation or a stale assignment leaves the source tab in place.

The torn-off window appears with the grabbed point on its measured sidebar row aligned to the release location, constrained to that display's usable frame. Placement is applied once before revealing the window; later sidebar layout changes do not move it. If the row cannot be measured promptly, the committed window appears at the drop location without discarding its tab.

## Scenes on iPhone and iPad

The mobile app declares a `WindowGroup` keyed by `BrowserWindowID` and supports multiple scenes on iPad. Each scene projects its own selections over the shared `BrowserStoreFamily`, so tab and Space edits reach other scenes immediately. Each scene owns a separate `MobileBrowserPageStore`, live WebKit views, native tab runtimes, and private browsing session. Sharing tab records does not share a live page or its form state between mobile scenes.

The macOS window coordinator, live-page handoff and mirrored preview, Blank Window commands, and tab tear-off placement are composed only by the Mac app. Mobile keeps its existing scene lifecycle and keyboard shortcuts; it uses the shared data and persistence safeguards without adopting those Mac presentation features.

## Credentials and privacy

Crest Passwords are stored in the Keychain and matched by origin. Each Space can disable Crest-owned suggestions, generation, save prompts, and HTTP-auth reuse without deleting its stored credentials. Sensitive reveals and exports require device authentication. Page-to-app credential messages are schema-checked and origin-bound.

The privacy manifest is shipped from `CrestShared/Resources/PrivacyInfo.xcprivacy`. The macOS app declares Apple's approved Web Browser Public Key Credential entitlement for system passkey access and the iCloud Passwords helper. Its signing profiles must include that capability; system passkey access also requires the user's authorization. Other managed capabilities remain gated on platform-specific Apple approval.

## WebKit boundary

Shared infrastructure decides navigation, downloads, content blocking, reader mode, authentication, permissions, failure recovery, and website data ownership. Platform roots provide the actual WebKit view host and native chrome. Shared policy adapts presentation to the current layout and input capabilities.

`BrowserFaviconSession` owns capture, fallback, and retry lifetime through a document adapter. Authenticated icon discovery stays inside the live WebKit context; public fallback remains credential-free and profile-scoped. Native pages invalidate requests on navigation and icon changes and stop them on removal.

`BrowserReaderModeSession` owns request cancellation and document changes through a document adapter. `BrowserWebKitCredentialSession` shares origin validation and filling while the platform page owns its WebKit host. On macOS, the shared runtime publishes a page's metadata and completed visits once through its current window owner. Other hosts use `BrowserPageSessionSynchronizer` with an exact, unlocked tab assignment; page stores validate the page before supplying its metadata.

Shared page operations own common navigation and media behavior. `BrowserPageContentRuleSession` tracks only Crest's content rules, and `BrowserTabStateCoordinator` owns archive eligibility and pending copies without retaining pages. Platform stores apply a shared reconciliation plan and retain their own presentation and memory-pressure policies. On macOS, each `BrowserTabRuntime` owns a tab's current and suspended WebKit configurations together with their history links, so releasing the tab releases every configuration it retained.

## Platform shape

Regular-width layouts share a persistent sidebar, page surface, Space switcher, pinned sites, saved tabs, current tabs, and archive. Compact-width layouts present the same data through compact navigation and sheets. Settings belongs in the browsing canvas at regular width and uses a sheet only at compact width; the current layout determines presentation, including after a window resize.

Shared views read independent interaction capabilities from their environment. Touch, hover, organization, and navigation transitions describe what the hosting shell supports; they are not device identities. Container width and Dynamic Type remain environmental inputs. Shared components own common content and actions, with accessory slots or optional actions for native presentation differences.

Each window and browsing mode owns a `BrowserSidebarInteractionState` for drag sessions and measured reorder geometry. The root supplies it to sidebar and page surfaces; repeated root composition reuses its live connection. Practice and previews compose their own owner. Geometry registration and target resolution are separate collaborators of the reorder lifecycle. `BrowserStore` reports session reset and tab relocation through a weak, domain-only observer, so application state never constructs or retains feature presentation.

Platform roots compose scenes, supply persistence and system services, host WebKit, and translate native input. Shared handlers own interaction state, source validation, cancellation, and commitment. Content-blocking reconciliation decides reload policy once, while platform page stores apply that decision to their resident pages.

Split large views at responsibilities such as a widget deck, media controls, or an import workflow. Keep related local helpers with their owner, reuse components wherever behavior repeats, and name interaction thresholds and design metrics where they are owned. Comments explain constraints and lifecycle decisions that the code cannot state directly.

The application supports Apple silicon only.

## Validation

Use focused tests for browsing state, persistence, privacy, and other durable behavior. Run the relevant tests and affected platform suite. Repository scripts cover identity, cache hygiene, browser fixtures, and release validation. Review layout, animation, and styling in the running app.

# Portable browser control plane

## Migration completion contract

Finish the original Crest UI on one portable browser core, with Chromium on
macOS and WebKit on iPhone and iPad. Keep WebKit available as a registered engine.
Preserve existing browser organization, Space isolation, native interaction and
customization. Desktop and mobile must converge through the same sync rules even
when they render pages with different engines. Deliver Crest-branded review
builds and a reproducible packaging path without replacing the installed app or
publishing a release as part of this migration.

The working Chromium host establishes that the rendering approach is viable.
It does not complete core ownership, sync, platform services or shipping
composition. The normal `Crest` and `CrestMobile` targets now use the same
`CREST_CORE_BACKED` state composition as `CrestChromiumUI`, `CrestNativeCore` and
`CrestMobileNativeCore`. `CREST_REVIEW_BUILD` separately enforces isolated launch
for the review targets. The normal Mac target still hosts WebKit; the native
Chromium distribution remains a separate packaging step. The live native app uses
`NativeSessionAuthority`; `BrowserSessionKernel` and its registered adapters
remain a separate integration path. Completion requires one production authority
and one capability contract, rather than maintaining two implementations of
browser behavior.

### Ownership after migration

| Owner | Responsibilities |
| --- | --- |
| .NET Domain and Application | Session and workspace rules; Spaces, profiles, tabs, folders, splits, history and archive; durable commands; sync projection, ordering, conflict and deletion policy; restore and migration rules; authorization decisions based on platform results |
| Engine adapter | Native page creation, rendering, input, navigation, engine history, page observations, origin permissions, downloads, popups and extension execution where supported |
| Apple platform services | CloudKit transport and account state, filesystem storage, Keychain and system authentication, OS permission dialogs, native download destinations, app lifecycle, signing and packaging |
| Existing SwiftUI/AppKit UI | Current layout and interaction, read projections, presentation state and commands; native card attachment and window presentation |

Native rendering, pointer input, scrolling and compositing stay in the engine.
They do not make round trips through JSON or the .NET command processor. A core
command owns the semantic transition; correlated adapter completions report
native work without becoming a second writer of browser state. Native image
assets and opaque engine data stay outside semantic records.

### Work order and acceptance

| Step | Work | Completion evidence |
| --- | --- | --- |
| 1. Finish core ownership | Move remaining Space, branding, preference, workspace, transfer, import, cleanup and restore decisions from Swift proposals to semantic commands. Consolidate the authority and kernel paths around the real UI. Keep existing checkpoint compatibility and fail atomically when a command cannot commit. | Mac and mobile native UI perform the same operations against the core. Multiple windows reconcile correctly; restart restores accepted state. Remaining Swift mutations are presentation or adapter work, with no parallel domain implementation. |
| 2. Move sync semantics | Port the existing record model, projection, order tokens, merge, materialization and tombstone policy to the core. Retain native CloudKit transport and account handling. Preserve wire compatibility and local-only records. | Focused record tests cover concurrent edits, delayed batches, explicit deletion, retention, older clients and restart. Chromium Mac and WebKit mobile then converge through real CloudKit in an isolated sync namespace, verified from records as well as UI. |
| 3. Finish engine and service integration | Use the same registered page/profile contracts in the real UI. Complete tab/window before-unload, Crest download ledger integration, favicons, restoration, profile deletion, transfers and recovery. Inventory current reader, translation, capture, print, media, authentication, notification and page-action callers; adapt each supported feature and remove dormant WebKit objects from the Chromium path. | Exercise each migrated user flow in the native app. Capability declarations match actual adapter behavior and govern UI availability. Close cancellation, private/locked Space boundaries and interrupted operations preserve state. Unsupported engine features have explicit product behavior. |
| 4. Complete native extensions | Preserve the restored toolbar, Site Controls, permission review, multi-Space installation and native Settings. Complete applicable action context menus, commands, extension-created windows and side panels. Keep Chromium responsible for verification, runtime permissions, updates and execution. Resolve iCloud Passwords through valid Crest signing and Apple's helper requirements. | uBlock Origin Lite filters real requests and retains profile settings. iCloud Passwords completes pairing and autofill with the properly entitled build and user participation where required. Installation, copying, removal and private access preserve Space ownership. |
| 5. Finish Crest identity and lifecycle | Package the Crest default icon, alternate artwork and Dock tile plug-in. Restore saved icon preferences at Chromium startup. Replace app-facing Chromium menu/About identity with Crest while retaining required engine attribution. Wire external links, reopen, quit, saved windows, browser registration and the intended update path into the host. | Finder, running Dock and Dock after quit use Crest artwork. Default/custom choices survive relaunch and appearance changes. App/menu version and identity are correct. External links and lifecycle actions reach the native Crest UI. |
| 6. Complete app composition and migration | Make the core the normal app composition on both platforms. Keep isolated review identities and explicit profile roots. Provide a safe import/upgrade path for existing Crest state, with recovery copies and no implicit WebKit-to-Chromium cookie or credential conversion. Document reproducible builds, required entitlements and engine distribution requirements. Remove obsolete experiment UI and duplicate migration paths once the real app covers their contracts. | Fresh install, existing-session upgrade, restart, offline editing, sync reconnect and private browsing work on Mac and mobile. Original UI remains intact. Relevant retained tests and release builds pass; temporary build outputs are cleaned. Every remaining external dependency is named, and unfinished requirements remain open. |

The Chromium packager includes Crest's default and alternate icon resources and
Dock tile plug-in. The native root restores the icon preference at startup. The
preference uses the experimental app's own domain so the Dock plug-in can read it
outside the browser process. The outer bundle reports Crest's version while the
engine framework retains its Chromium version. The Chromium host installs Crest's
AppKit menus and About identity. Those menus
and native keyboard events use the existing command actions and persisted shortcut
assignments. Blank and Quick Windows mount their original native views; Quick
Window dismissal releases its lease and promotion returns it to its source
workspace. Unsupported page services remain disabled until their adapter is wired.
Remaining identity work includes external links and normal distribution composition.

Validate coherent user flows as they are wired into the app. Retain focused tests
for state, persistence, synchronization, ownership and authorization. Do not make
another synthetic UI or repeat long engine benchmarks for unrelated changes.
Recheck performance when changes affect engine flags, scheduling or page
attachment. Commit complete sections with the repository's version and release
note requirements.

### Cross-engine sync contract

The existing CloudKit format is engine independent: Space and profile identifiers,
Space appearance and browsing preferences, folders, HTTP/HTTPS tabs and their
saved/pinned placement, split membership, history and archive. Existing user sync
preferences still decide which optional record categories participate. CloudKit
record identifiers, logical clocks, device identifiers, supported schema versions
and encrypted payload encoding must survive the move to the core.

The same tab ID and URL can therefore become a Chromium page on Mac and a WebKit
page on mobile. A profile UUID is the shared logical identity; its on-device
Chromium directory or WebKit data store is an adapter detail. Engine selection
and capabilities belong to the local platform. A device must not delete a shared
record merely because it lacks a capability.

Cookies, sessions with websites, raw engine history stacks, caches, open native
page handles, device permissions, extension packages and their granted access do
not enter browser-record sync. Native Settings/Start pages, `chrome://`,
`chrome-extension://`, files and other non-HTTP/HTTPS tabs stay local and survive
incoming merges. Private and temporary workspace records do not upload. A locked
Space's records may participate in existing sync policy without creating pages or
bypassing the local authentication requirement.

Chromium extension installation and copying currently operate within local Space
profiles. The old `extensionSettings` sync preference remains decode-compatible
but contributes no extension records. Mobile must not install Chromium extensions
or revive WebKit extension emulation. Any later extension-list sync needs an
explicit portable intent model and local permission review; it is not implicit in
this browser-record migration.

`NativeSyncSessionTransition` prepares local staging, record merging,
materialization, repair and retention as one core operation. The session authority
then reserves the validated replacement while the Apple storage adapter commits
the matching session, per-Space history and journal in one SQLite transaction.
Failed storage cancels the reservation; accepted storage publishes the reserved
revision before native windows reconcile. A restart reads the committed pair.
Preserve ordering between local edits, incoming batches, durable checkpoints,
pending uploads and acknowledgements, including crash recovery. Keep explicit
deletion distinct from absence, retention and superseded records, and preserve
unknown fields supported by the compatibility contract.

The experimental Chromium launch creates an isolated CloudKit controller and
does not start production sync. Removing that protection is not a sync migration.
Live cross-device validation opts into a separate review record zone through
explicit launch configuration and provisioned app identities. Keep sample sessions and test
tombstones out of the installed app's journal and cloud records. Simulator builds
and an idle sync indicator cannot substitute for two-client record convergence.

### Completion gate

Do not close the migration after a successful Chromium launch or extension demo.
It is complete when the real desktop and mobile compositions share core behavior,
cross-engine sync has live convergence evidence, retained user features have their
engine/platform adapters, Crest identity and customization work, and existing
sessions upgrade without loss. Keep external signing, provisioning or device
access requirements visible; do not mark those requirements complete on the
strength of unit tests or an unrelated successful build.

## Native engine boundary

The existing desktop and mobile page facades use `BrowserPageEngine` for native
view ownership, loads, Back/Forward history, reload, stop, zoom, Find, viewport
capture and media residency observations.
`BrowserWebKitPageEngine` owns WebKit's supplemental same-document navigation
history on both Apple platforms. `ChromiumNativePage` implements that same port
using the Chromium host. History entries remain read projections; traversal and
cache-bypassing reloads run in the engine's navigation controller.

Native page operations do not require a .NET round trip. The UI calls a shared
native port, and the selected engine implements it. .NET remains responsible for
shared session state and policy. The process host presents windows through
`BrowserMacWindowPresenting`; batch page confirmation uses the optional
`BrowserPageClosePreparing` service injected by the composition. Chromium's
before-unload confirmation leaves pages alive until the session accepts the
close. Canceling it preserves the tab, archive and renderer. Engine-specific
calls belong inside the adapter or its process composition, not shared commands
or views.

Each desktop composition constructs exactly one native engine. Chromium pages
have no WebKit view; WebKit document controllers are optional and are only
created for a WebKit page. Chromium snapshots come from its compositor, and
idle-tab decisions use Chromium playback, capture and picture-in-picture state.
Missing media observations keep the page resident until its engine can answer.

The process composition now registers its native engine with each core session
using the same versioned descriptor schema as the message adapters. Registration
is local, immutable for that session, and excluded from persistence and sync.
A restored session accepts the destination device's engine without changing shared
browser records. Required page/navigation contracts must be supported at version
1; unverified, unavailable and unknown capabilities do not authorize a feature.
The native page port exposes this declaration without crossing the ABI for each
interaction. Document export, printing, full-page capture and inspector commands
now use native engine services. Save panels and print sheets remain native UI.
The command route and developer capture controls consult the registered services;
Chromium exports PDFs, full-page PNG captures and MHTML archives through a fixed,
page-scoped in-process DevTools client. It exposes no debugging socket or arbitrary
protocol commands to the UI. Navigation, renderer loss and page closure cancel a
pending export; requests time out after 45 seconds. Full-page captures use the
same 6,000-by-24,000 CSS-pixel bounds as WebKit, and export data is limited to 64 MiB.
Archives use the engine's actual format: `.mhtml` for Chromium and `.webarchive`
for WebKit. Chromium printing renders a PDF and presents the native PDFKit print
sheet, whose paper settings scale the rendered pages. Reader and Apple translation
still need Chromium adapters. Its inspector currently opens DevTools without
selecting a requested panel. Local-file opening also remains to be wired into the
native command route; entering a `file://` archive path in the current address
resolver does not reopen it.
The original message-based adapter/kernel and page creation/lifetime composition
also remain separate. This boundary does not finish the core authority migration.

## Existing UI migration

`CrestNativeCore` and `CrestMobileNativeCore` build the existing platform entry
points, all original native views, and the current page infrastructure. Each has
an isolated bundle and profile.
`CREST_CORE_BACKED` routes migrated domain operations through the packaged .NET
library without changing their callers. Tab opening, activation, duplication,
closing, deletion, placement, filing, renaming, residency preferences, folders,
split groups, archive restoration, and automatic tab cleanup execute through the core.
Address intent, history visit policy,
history-range deletion, and history/archive retention also use the library.
Each store family has one `BrowserCoreSessionAuthority`. The .NET authority owns
committed session records and revisions; Swift retains an accepted read projection
for the existing UI. Native edits cross as changes to individual records and
collection order, without resending unchanged history or favicon bytes. Revision
checks reject stale proposals. Transfers between families commit both graphs
before either native window reconciles its selection.

The core captures immutable checkpoints and encodes the session and per-Space
history on the native persistence worker. Editing can continue while an older
checkpoint is being saved. The existing storage adapter retains the established
UserDefaults keys, load/recovery path, scoped writes and favicon side store.
Per-window selection is projected into each checkpoint, including deliberately
empty windows. Private and temporary families remain backed by memory storage.

This moves live state ownership and checkpoint serialization into the core.
Remaining native domain operations still submit prepared value changes; replacing
those proposals with semantic core commands is a separate part of the migration.

The store's tab opening, activation, closing, deletion, current-tab clearing,
renaming and residency actions now send commands directly to that authority.
Folder creation, appearance, renaming, collapse, deletion, moves and tab filing use the same path.
Requests contain arguments and window selection rather than an encoded Space.
The core prepares the edit against its owned records, the native adapter decodes
the resulting projection, and a revision-checked commit publishes both sides.
Abandoned preparations do not change state. Favicon bytes stay native, and
existing history and archive records do not cross the command boundary.

Space creation, identity, appearance, preferences, default selection, saved-tab
disclosure, reordering and removal also use the authority's commands. Profile
identity is checked before editing; borrowed workspaces cannot change their source
profiles. The core enforces new private Space defaults and prevents removal of
the last Space. Native profile cleanup and authentication remain platform work.

Portable archive import, reviewed import, and manual setup use one core workspace
operation for both preview and commit. The core merges folders, enforces Space
and pin limits, preserves existing profile identities, repairs imported identity
collisions, applies draft ordering, and graduates a reviewed first-install seed.
Native code supplies the reviewed intent and opaque appearance vocabulary;
favicon bytes are reattached using positional references returned by the core.
Accepted imports reserve publication while the session and sync journal are
saved together, then reconcile all windows. Rejected and stale preparations
cannot publish or reserve storage. The Chromium process host presents the original
setup/import window through the native window port, including completion and
dismissal; the SwiftUI app continues to use its existing scene.

Cross-Space tab moves and same-profile temporary-window transfers prepare from
the core's owned records. The core decides placement, split cleanup and
destination selection, and validates the source window's fallback selection. A workspace transfer reserves both revisions
until the persistent owner's session and sync journal are saved; cancellation
leaves both graphs unchanged. Private browsing and stale profile identities
cannot cross that boundary. The native coordinator moves the existing page
through the engine adapter after the state commit, without navigating it again.
Compact transfer projections exclude history, archive and native image bytes.

`crest_core_evaluate_sync` runs wire-compatible conflict resolution and stable
fractional ordering in the core. Record identity is validated on both sides of
the boundary. `NativeSyncJournal` owns immutable journal snapshots: local staging,
deletion evidence, incoming merges, cloud replacement, logical clocks and upload
acknowledgements. Swift value copies retain a shared snapshot handle; a mutation
creates a separate handle and publishes its decoded projection only on success.
The persistence adapter writes the core-encoded snapshot in the existing format.
Failed operations leave the original records, clock and pending uploads intact.

`NativeSyncProjection` maps compact native checkpoints to the existing shared
record format. Staging projects directly inside the immutable journal transition,
so projection failures cannot advance its clock. `NativeSyncMaterializer` applies
reconciled incoming records, preserves device credentials and local-only pages,
and distinguishes delayed parent folders from tombstoned folders. Domain folder
resolution holds back incomplete subtrees and rejects cross-Space ancestry.
Prepared query handles evaluate once and return typed identity-bearing errors.
Native favicon image bytes stay outside the core and are reattached by the adapter.

`NativeSessionMaintenance` repairs checkpoint identities, folder structure,
selection, pin limits and split membership, and applies history/archive retention.
The same domain split policy serves command edits and checkpoint repair. A repair
returns native asset references separately from semantic records, preserving each
tab's images when duplicate identities are replaced. Startup must accept repair
before creating pages or saving the session; rejected sync preparation leaves the
original session and journal untouched. Replacing a disposable seed with real
cloud Spaces clears the seed marker.

`crest_sync_session_prepare` returns a matched session result and immutable journal
handle after all merge rules succeed. `crest_session_reserve_replacement` validates
the replacement before any durable write and excludes competing core writes until
publication or cancellation. Core-backed persistent compositions use
`BrowserTransactionalSessionPersistence`; legacy defaults are migrated once and
retained for rollback. Local saves, incoming sync and upload acknowledgments use
one serial storage queue. Startup stages restored local edits before cloud work,
including edits saved before their coalesced sync projection completed.

`NativeSyncAuthority` is attached to the persistent session authority and owns the
accepted journal, the latest local revision and pending publication. Private and
temporary workspaces cannot attach it, and one sync owner cannot serve unrelated
store families. Preparing a candidate does not publish it. The core rechecks its
revision before storage; an edit arriving during storage advances the revision
barrier without waiting for encoding or allowing a later stale snapshot to win.
Incoming merges bind their journal transaction to the session replacement, so
both core values publish under the same lock after SQLite commits. Swift retains
read projections and schedules native background work and storage.

Sync compares UUID fields by identity and timestamps by their exact binary date
value. Different JSON number spellings from native encoders do not create edits;
logical clocks retain integer precision and ordinary strings remain case-sensitive.

Native record projections preserve additive encrypted payload fields through
CloudKit decoding, journal persistence and uploads. Core restaging carries those
fields forward using the supported payload vocabulary. Known optional fields
can still be cleared, and group/provider metadata follows member identity rather
than array position. Deleted members and tombstoned payloads are not resurrected.
New incompatible schemas still require a newer client.

Live cross-engine CloudKit validation must compare record identities and versions,
including fresh-profile adoption and repeated merges. An unreadable transactional store currently
stops startup with the file preserved; a native recovery flow is still needed.
Native presentation codecs continue to normalize platform glyphs and branding values.

Value-only operations still use `crest_core_edit_session`, which receives one
compact Space and returns an atomic edit.
It excludes images, history and existing archive records. The native projection
keeps those records and presentation metadata, applies the returned tab/folder
values, and reconciles native pages through the existing pools. The core's
`BrowserTabCollection` contains the organization rules shared with the asynchronous
kernel; profile access and page lifetime remain separate responsibilities.

`crest_core_evaluate_policy` is a bounded, synchronous pure-function boundary:
it performs no I/O, engine operation, callback, or wait on the asynchronous
executor. The same domain rules also serve the asynchronous browser kernel.
Record-removal calls send batches of timestamps and receive indices; they carry
no page objects, URLs, titles, profile data, or complete session snapshots. The
native caller validates all batches before applying a category's removals. Its
existing persistence scopes and sync tombstone rules remain in use.
Engine effects and the remaining command orchestration move behind the existing
store/page interfaces in coherent sections. The original UI, layout, and
interaction behavior remain the frontend.
The standalone control-plane targets below are contract harnesses, not a
replacement product UI. New product integration belongs in the existing UI target.

The experimental `CrestControlPlane` and `CrestControlPlaneMobile` targets separate semantic browser decisions
from native engine and presentation work. The normal `Crest` and `CrestMobile`
targets continue to use their existing composition roots.

## Ownership and dependencies

| Module | Responsibility |
| --- | --- |
| `CrestCore.Domain` | Workspace, Space, profile identity, tab organization, per-window selection, history and archive rules |
| `CrestCore.Application` | Serialized command processing, native effects, correlation, projections, bounded queues |
| `CrestCore.Contracts` | Strict JSON parsing, provider descriptors, protocol validation |
| `CrestCore.Native` | Exception-contained Native AOT C exports and numeric handles |
| `CrestShared/Infrastructure/ControlPlane` | Original UI adapters, accepted session projections and checkpoint handles |
| `CrestNative/Apple/CoreClient` | Swift message transport and read-only projection types |
| `CrestNative/Apple/Composition` | Experimental native app, composition, and surface attachment |
| `CrestEngines/WebKit` | Adapter around the existing `BrowserPage` and `MobileBrowserPage` |
| `CrestEngines/Chromium/Apple` | Native SwiftUI framework and Objective-C engine port |
| `CrestEngines/Chromium/Overlay` | Chromium BrowserWindow, profiles, TabStripModel adoption and native observations |

In the standalone contract harness, the domain references no JSON, filesystem,
Apple, or Chromium APIs. The application
emits native work as data. Its caller dispatches that work on the correct native
thread and reports the outcome. SwiftUI reads core projections and sends commands.
`BrowserStore` is never constructed for this session, so it cannot compete with
the core as a writer. WebKit still owns live pages, history stacks, rendering,
input, dialogs, and native security decisions.

The experimental app has a separate bundle identity and a separate atomic session
checkpoint. WebKit stores remain nonpersistent per profile. There is no credential vault, CloudKit startup,
and no updater startup. Platform services receive isolated launch settings before
construction. This is an experimental app for migration work, not a production
profile migration or feature-complete replacement for Crest.

## Migration boundaries

The table includes facilities implemented in the standalone kernel. Its remaining
integration column describes work still needed in the original UI composition.

| Existing owner | Core destination | Remaining integration |
| --- | --- | --- |
| `BrowserStore+TabLifecycle`, `BrowserSession+Tabs` | Tab commands, organization and accepted session ownership now used by the original UI | Direct commands against the owned session and native page effects |
| `BrowserStoreSelection`, `BrowserWindowState` | Durable window-scoped selection, acknowledged group handoff and destination failure rollback | Full window chrome bindings |
| `BrowserStore+Workspaces`, `BrowserStoreFamily` | Core session ownership and atomic cross-family edits in the original UI; workspace lifecycle in the kernel | Move native workspace orchestration and profile lifetime behind core commands |
| `BrowserStore+Spaces`, `BrowserSession+Organization`, address/search policy | Space/profile, organization, address resolution, search/content-blocking preferences and resumable deletion | Full branding and production profile deletion adapters |
| `BrowserStore+Folders`, split-group domain | Nested folders, tab boundaries, subtree moves, filing, duplication, split mutations and multiple native page presentation | Batch close, appearance commands and full native UI bindings |
| Page pools and platform page stores | Registered page/profile ports | Wrap both platform pools, preserve scene/runtime lifetime and recovery |
| Chromium extensions | Engine-owned extension runtime with restored native toolbar, Site Controls, installer and Settings | Remaining extension UI parity, commands, windows, side panels and credential-helper signing; WebKit extension support is removed |
| Persistence and sync coordinators | Original UI saves immutable core checkpoints in the existing Codable format; kernel provides revisioned saves and Space tombstones | Production import, core restore/migration rules and sync reconciliation |
| Permission/credential/download services | Core policy with native continuations | Preserve document/origin scope and native consent flows |

`BrowserSessionKernel` routes windows and native pages to their owning workspace.
Only the persistent workspace receives a storage provider. Private workspaces have
fresh profile identities and Crest’s private search/retention defaults. Temporary
workspaces borrow a source profile, while their tabs, folders, history, archive and
selections remain separate and memory-only. Profile policy has one canonical
writer. Closing an owner revokes dependent workspaces; its native profile is
released after their acknowledgments. Native page creation must drain before
workspace disposal. A stale popup offer is rejected instead of being moved to a
persistent workspace.

In the standalone kernel, Space deletion saves an intent before disposing native profiles. Dependent
workspaces lose access and release their native pages first. Engine cleanup and
service cleanup have separate correlated acknowledgments; failure retains a
pending Space that can be retried. Completed tombstones remain in the checkpoint
and reject stale Space/profile records. WebKit implements deletion for its
isolated in-memory profiles. The native Chromium cleanup port described below
is separate from this message-based path. The native app now saves a matching
core-owned deletion intent and resumes its local adapters at launch. Consolidating
the two application paths and capability contracts remains migration work.

The standalone harness uses a small contract-testing UI. Product migration uses
the original Crest UI in the NativeCore targets. In the harness, native feature tabs
are modeled separately and do not create engine pages. Two windows can have
independent empty selections. Selecting a tab owned by another window first issues
a detach lease to that window. Only its matching acknowledgement commits the new
selection and issues the destination attachment. Superseded handoffs cannot steal
the current selection through late native callbacks.

Native history and archive tabs query bounded pages of records from the core.
Search, reopening, restoration and deletion preserve workspace ownership and
locked-Space access rules. The UI owns only query presentation.

The core restores legacy tab, folder, history, archive and window descriptors
without creating native pages. Selecting a dormant page creates a new page identity
and generation. Unknown additive JSON fields survive checkpoint round trips.
`CoreSessionStorage` owns only byte storage and an exclusive writer lock. The core
coalesces revisions behind the current save, and shutdown remains blocked after a
failed save until a retry succeeds. This checkpoint does not import the installed
application's data or enable CloudKit synchronization.

Content-blocking policy lives in the core and is shared by profile borrowers.
The WebKit adapter compiles Crest's existing balanced rules in an isolated cache,
installs them before new-page navigation, and applies changes to existing pages
on their next navigation. Native compilation failures remain visible and retryable.

The new WebKit adapter retains the existing popup delegate and adopts its exact
native page, preserving the opener and original request. Its registration still
declares extensions unavailable. WebKit extension installation, emulation,
runtime coordination have been removed. The Chromium host reuses the native
extension presentation components with Chromium-owned profile state. Before-unload,
download and permission integration through the asynchronous adapter remain
unverified; their native browsing implementations remain in the actual app.
Chromium registration must likewise reflect the capabilities of the actual built
host, rather than assuming Chrome compatibility from the engine name.

## Build workflow

Install .NET SDK 10.0.201 or a servicing patch, Xcode, and XcodeGen. Regenerate
`Crest.xcodeproj` with `xcodegen generate` after changing `project.yml`.

The normal `Crest` and `CrestMobile` targets build and embed their core from source.
`Scripts/control-plane/build-apple-core.py` selects the runtime for the destination,
uses Release NativeAOT for both Debug and Release apps, and caches it under the
current build's products directory. Source, SDK and platform changes invalidate
the cache; concurrent target requests share a build lock. NativeAOT intermediates
also stay in Derived Data. No managed runtime is required on the user's device.
Explicit `CREST_CORE_LIBRARY_DIR` or `CREST_CORE_FRAMEWORK_DIR` overrides use a
previously published library, so callers must keep it matched to the checked-out
contracts. The existing review scripts use those overrides.

CI installs the pinned SDK with Microsoft's [SDK install script](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-install-script)
through `Scripts/control-plane/install-dotnet.sh`. Local Xcode builds find `dotnet`
in PATH, `~/.dotnet`, or the standard macOS SDK location; `CREST_DOTNET` can select
another installation. Network access is needed for the first SDK/package restore.

Core ownership no longer implicitly enables isolation. `CREST_REVIEW_BUILD`
forces isolation in the review apps; tests and previews use the existing launch
policy. To review the normal Mac target without registering the installed app's
identity, set `CREST_MAC_BUNDLE_IDENTIFIER` to a separate identifier and
`CREST_MAC_ENTITLEMENTS` to its compatible entitlements, then launch with
`CREST_ISOLATED_SESSION=1` and a unique `CREST_ISOLATED_PERSISTENCE_ID`.
Normal device provisioning and the remaining physical-device migration validation
are still required before distribution.

Build an isolated app into a new absolute path:

```sh
Scripts/control-plane/build-experiment.sh /absolute/new/path/CrestNativeCore.app
```

The script runs the managed and native ABI checks, builds the original macOS UI
with the migrated policies, and
removes its temporary Derived Data on exit. The resulting app contains the
self-contained core library and does not require an installed .NET runtime.
`Scripts/control-plane/build-ios-experiment.sh` builds the original iOS UI for Simulator
app with the same output-path convention and temporary-data cleanup.

For core-only development, run `dotnet test tests/CrestCore.Tests` from
`CrestCore`. See [the contract](../../CrestContracts/README.md) before adding a
command or provider. Frequent page observations use incremental tab projections
and stable observed row objects. Oversized structural snapshots stream in bounded
chunks and become visible only after complete digest validation. Creation limits
follow the existing import policy: 64 Spaces and 5,000 tabs per Space. The
checkpoint remains limited to 16 MB, so large binary metadata must move to a
separate blob provider before increasing that storage budget. Full UI behavior
at the import limits still requires validation.
Physical iOS packaging and runtime validation are required before
removing the existing shared Swift authority.

For iOS, publish `CrestCore.Native` for `ios-arm64` or `iossimulator-arm64` with
`-p:PublishAotUsingRuntimePack=true`. Package the resulting dylib using
`Scripts/control-plane/package-apple-core.py`, then build `CrestMobileNativeCore`
with `CREST_CORE_FRAMEWORK_DIR` set to the containing directory. The framework's
platform must match the Xcode destination. This app uses its own bundle identity
and requests CloudKit only in provisioned device builds, without the production browser credential entitlement. Simulator execution does
not replace physical-device validation.

## Chromium host

The host overlay uses Chromium's browser startup, Browser and TabStripModel.
Its BrowserWindow implementation loads `CrestChromiumUI` after browser startup.
The framework compiles the original `CrestShared` and `CrestMac` views and services,
then mounts `BrowserMacApplication.browserWindowContent` in native windows. It has
no `@main` and does not replace Chromium's application delegate. The temporary
`ControlPlaneWindow` is no longer the Chromium product interface.

`CREST_CORE_BACKED` uses the same .NET session authority and domain commands as
`CrestNativeCore`. `ChromiumNativePage` creates a WebContents for the existing
`BrowserPage` and mounts its NSView inside the original page card. Navigation,
Back, Forward, reload, stop, title, URL and loading observations cross the native
host port. The existing pools still own page lifetimes and window presentation.
Engine effects have not yet moved to the asynchronous core dispatcher in this
composition and do not need that additional hop: page operations use the shared
native engine port, while portable session changes remain core-owned. The separate
`ChromiumAdapter` remains the kernel adapter for the contract harness.

Each Space uses a regular Chromium profile under the explicit experimental
user-data directory. Crest's native session uses its own isolated defaults suite,
separate from both production and the WebKit review app. Packaging includes the
original UI resources and Sparkle dependency; isolated startup disables updates
and CloudKit by default. Chromium quit requests run native before-unload and download checks,
then flush native persistence before disposing pages.

The original private-window composition uses a separate in-memory Chromium
profile for each private Space. Closing that window releases its pages and
profile; reopening starts a fresh session. Popup adoption attaches the existing
WebContents to a core tab, preserving opener relationships and document state.
Unowned or stale popup offers are rejected.

Find uses an engine-neutral configuration, while Chromium supplies page search,
zoom and DevTools. Site Controls reads and changes Chromium's origin permissions;
permission requests use native sheets attached to the owning Crest window.
Extension actions use the active page's profile and Chromium's real action runner,
popup host, service workers and permission enforcement. Private windows only
expose extensions explicitly enabled for incognito use. Crest's original toolbar,
Site Controls grid, and install Space picker consume an observable native model;
Chromium owns action execution, installation, permissions, updates, and pin state.
Native Extensions settings provide Space-scoped management and copying, with a
link to Chromium's advanced manager. CRX verification precedes the native consent
review, and additional Space installations reuse only the explicitly reviewed
package and permission identity.

Extension action content is hosted in an AppKit popover anchored to the native
button view. AppKit handles screen-edge placement and movement; Chromium retains
the popup renderer and extension lifecycle. Internal browser addresses use
`crest://` in Crest's session and address controls. The Chromium adapter translates
them to `chrome://` for navigation and translates observations back, preserving
paths, queries and fragments. Web URLs and `chrome-extension://` security origins
are unchanged. Internal navigation remains gated by the engine capability.

The native menu bar uses Crest's commands and shortcut preferences. Individual
tab and window closure preflights Chromium pages before committing the shared
session change. A canceled close preserves the pages and their unsaved state.
Chromium download observations feed the existing native download ledger through
`BrowserEngineDownloadControlling`. Per-Space destinations use the Apple platform
resolver. Transfer progress stays local to the adapter, while retention settings
remain core-owned. Restored records retain their original creation times and
do not become new-download notifications. Clearing or expiring a record removes
engine download history while preserving completed files. Destination selection never supplies an implicit safety
override. Explicit warning decisions are checked against the current engine
verdict; policy blocks and known malware cannot be approved through this bridge.

Chromium publishes favicon changes into the existing native tab projection.
Opaque navigation archives carry an engine and version tag, remain local to the
profile, and never enter the portable session or CloudKit records. Chromium uses
its sanitized session-entry serializer; WebKit keeps its own interaction state,
including support for older untagged WebKit archives. An incompatible archive
falls back to the tab's saved URL. Named review launches keep separate archives;
private and ephemeral sessions do not persist them. Quit captures resident pages
before flushing writes and disposing the engine.

Space data cleanup uses `BrowserEngineProfileRemoving`, injected alongside the
page adapter. Page pools release the Space's pages across native windows before
calling that port. The WebKit implementation removes its identified website data
store; the Chromium implementation revokes pending pages, popups, private profile
borrowers and extension observations, then uses Chromium's profile deletion
service. It waits for browsing-data removal and the durable engine deletion
marker before returning success. Chromium can finish removing the profile
directory on its next startup. Completed download files remain on disk.

The native app saves a core-owned Space/profile/operation intent before native
cleanup starts. That Space becomes unavailable across its windows; stale edits,
profile replacement and deletion of the last available Space are rejected by the
core. Cleanup retries are idempotent, and launch resumes saved intents through the
selected engine and credential adapters. A failed adapter keeps the intent for
another attempt. Private session reset discards its in-memory intents and creates
fresh profile identities.

Prepared semantic commands reserve publication while Apple storage writes. Final
Space removal and its explicit sync tombstones share one SQLite transaction, then
the core publishes both accepted values. A failed storage commit publishes
neither. Pending cleanup remains local during sync merge or replacement and never
republishes a remote tombstone as an active Space. An accepted explicit Space
deletion from another device creates the same local intent for the existing
profile. A sealed sync reservation persists the intent and accepted journal
together before the registered engine adapter runs. Absence from a cloud
snapshot, retention, and child-record deletions do not authorize profile cleanup.
Adapter failures retain the intent for the next sync or launch; windows cannot
reopen that profile while cleanup is pending.

There are still migration gaps.
Other WebKit-specific page tools and extension side panels need
their Chromium adapters.
Profile capabilities must describe this actual integration
before features are advertised as supported.

See [Chromium source preparation](../../CrestEngines/Chromium/README.md) for the
pinned build workflow.

The engineering package is design input, not an implemented SDK. Its suggested
commit, publication, and report-storage workflow does not override repository
instructions or authorize external actions.

## Isolated CloudKit review

A provisioned review app can opt into real transport with `CREST_ISOLATED_SESSION=1`,
its own `CREST_ISOLATED_PERSISTENCE_ID`, and `CREST_ISOLATED_CLOUD_SYNC_ID`.
The cloud ID is a shared lowercase ASCII slug of at most 48 characters. Devices
with the same cloud ID use `CrestReview-<id>`; each device keeps its own local
profile ID. Tests, previews, unnamed profiles and malformed cloud IDs cannot opt
in. The transport scopes fetches, writes, references and deletion handling to
that zone. Its cursor and server metadata live separately from production,
partitioned by local profile, container and zone.
Fresh cloud review profiles use the disposable first-install seed, so an existing
cloud session replaces their sample Spaces before publication. Restored profiles
keep their existing identities; equal Space names alone never imply duplication.

Device builds of `CrestMobileNativeCore` request CloudKit without the production
browser entitlement. For macOS provisioning, build `CrestNativeCore` with
`CREST_NATIVE_CORE_ENTITLEMENTS=CrestNative/Apple/Composition/MacCloudReview.entitlements`.
Its `CREST_NATIVE_CORE_BUNDLE_IDENTIFIER` may be set to the Chromium experiment
identity when obtaining that profile. Automatic development signing must grant
the review identity access to Crest's container. Chromium packaging accepts the
resulting profile through `--provisioning-profile`; it validates the identity and
CloudKit grant, embeds the profile, and preserves Chromium's runtime entitlements.
The review package uses the Development CloudKit environment. CloudKit access
does not grant Apple's browser password-helper entitlement.

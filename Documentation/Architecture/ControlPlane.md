# Portable browser control plane

## Migration completion contract

Crest runs its original UI on one portable browser core, with Chromium as the
default engine on macOS and WebKit on iPhone and iPad. WebKit stays a registered
engine on macOS too, as the alternate desktop build. Existing browser
organization, Space isolation, native interaction and customization carry over.
Desktop and mobile converge through the same sync rules even when they render
pages with different engines.

Every composition uses the same core-backed state: the WebKit `Crest` and
`CrestMobile` targets, the review targets, and the Chromium frameworks. The
Chromium host builds as `CrestChromiumUI` for review and as
`CrestChromiumUIProduct` without `CREST_REVIEW_BUILD`. `package-chromium-host.py
--product` assembles the product into Crest's own desktop identity, and the
experimental release workflow signs and notarizes it and publishes it as the
default download on the experimental channel, with the WebKit build beside it
as the alternate. `CREST_REVIEW_BUILD` forces isolated launch for the review
targets. Each store family's session lives in `NativeSessionAuthority`, and
browser behavior has one implementation. The remaining work is live sync
convergence and device validation, listed in [Engine abstraction
status](EngineAbstractionCompletion.md).

### Ownership after migration

| Owner | Responsibilities |
| --- | --- |
| .NET Domain and Application | Session and workspace rules; Spaces, profiles, tabs, folders, splits, history and archive; durable commands; sync projection, ordering, conflict and deletion policy; restore and migration rules; authorization decisions based on platform results |
| Engine adapter | Native page creation, rendering, input, navigation, engine history, page observations, origin permissions, downloads, popups and extension execution where supported |
| Apple platform services | CloudKit transport and account state, filesystem storage, Keychain and system authentication, OS permission dialogs, native download destinations, app lifecycle, signing and packaging |
| Existing SwiftUI/AppKit UI | Current layout and interaction, viewed Space and tab selection, read projections, presentation state and commands; native card attachment and window presentation |

Native rendering, pointer input, scrolling and compositing stay in the engine.
They do not make round trips through JSON or the .NET command processor. A core
command owns the semantic transition; correlated adapter completions report
native work without becoming a second writer of browser state. Native image
assets and opaque engine data stay outside semantic records.

### Work order and acceptance

| Step | Work | Completion evidence |
| --- | --- | --- |
| 1. Finish core ownership | Move remaining Space, branding, preference, workspace, transfer, import, cleanup and restore decisions from Swift proposals to semantic commands. Consolidate the remaining Swift mutations around the real UI. Keep existing checkpoint compatibility and fail atomically when a command cannot commit. | Mac and mobile native UI perform the same operations against the core. Multiple windows reconcile correctly; restart restores accepted state. Remaining Swift mutations are presentation or adapter work, with no parallel domain implementation. |
| 2. Move sync semantics | Port the existing record model, projection, order tokens, merge, materialization and tombstone policy to the core. Retain native CloudKit transport and account handling. Preserve wire compatibility and local-only records. | Focused record tests cover concurrent edits, delayed batches, explicit deletion, retention, older clients and restart. Chromium Mac and WebKit mobile then converge through real CloudKit in an isolated sync namespace, verified from records as well as UI. |
| 3. Finish engine and service integration | Use the same registered page/profile contracts in the real UI. Complete tab/window before-unload, Crest download ledger integration, favicons, restoration, profile deletion, transfers and recovery. Inventory current reader, translation, capture, print, media, authentication, notification and page-action callers; adapt each supported feature and remove dormant WebKit objects from the Chromium path. | Exercise each migrated user flow in the native app. Capability declarations match actual adapter behavior and govern UI availability. Close cancellation, private/locked Space boundaries and interrupted operations preserve state. Unsupported engine features have explicit product behavior. |
| 4. Complete native extensions | Preserve the restored toolbar, Site Controls, permission review, multi-Space installation and native Settings. Complete applicable action context menus, commands, extension-created windows and side panels. Extension-created windows, side panels and keyboard shortcuts compile and link in the pinned Chromium build; their runtime behavior still needs product review. Keep Chromium responsible for verification, runtime permissions, updates and execution. Resolve iCloud Passwords through valid Crest signing and Apple's helper requirements. | uBlock Origin Lite filters real requests and retains profile settings. iCloud Passwords completes pairing and autofill with the properly entitled build and user participation where required. Installation, copying, removal and private access preserve Space ownership. |
| 5. Finish Crest identity and lifecycle | Package the Crest default icon, alternate artwork and Dock tile plug-in. Restore saved icon preferences at Chromium startup. Replace app-facing Chromium menu/About identity with Crest while retaining required engine attribution. Wire external links, reopen, quit, saved windows, browser registration and the intended update path into the host. | Finder, running Dock and Dock after quit use Crest artwork. Default/custom choices survive relaunch and appearance changes. App/menu version and identity are correct. External links and lifecycle actions reach the native Crest UI. |
| 6. Complete app composition and migration | Make the core the normal app composition on both platforms. Keep isolated review identities and explicit profile roots. Provide a safe import/upgrade path for existing Crest state, with recovery copies and no implicit WebKit-to-Chromium cookie or credential conversion. Document reproducible builds, required entitlements and engine distribution requirements. Remove obsolete experiment UI and duplicate migration paths once the real app covers their contracts. | Fresh install, existing-session upgrade, restart, offline editing, sync reconnect and private browsing work on Mac and mobile. The existing-session upgrade is covered by a test that carries a real installed defaults session, its per-Space history, its favicons and its sync journal into the checkpoint and proves the second launch does not repeat it; see "Upgrading an installed session". Physical-device and real-account runs against installed Spaces remain open. Original UI remains intact. Relevant retained tests and release builds pass; temporary build outputs are cleaned. Every remaining external dependency is named, and unfinished requirements remain open. |

The Chromium packager includes Crest's default and alternate icon resources and
Dock tile plug-in. The native root restores the icon preference at startup. The
preference lives in the app bundle's own defaults domain, or the domain its
Info.plist names, so the Dock plug-in can read it outside the browser process. The outer bundle reports Crest's version while the
engine framework retains its Chromium version. The Chromium host installs Crest's
AppKit menus and About identity. Those menus
and native keyboard events use the existing command actions and persisted shortcut
assignments. Blank and Quick Windows mount their original native views; Quick
Window dismissal releases its lease and promotion returns it to its source
workspace. Unsupported page services remain disabled until their adapter is wired.
External URL and document opens, Dock reopen and saved normal windows now reach
the native UI: Chromium's `AppController` hands opens to Crest's own external-URL
policy and Space or Quick Window routing, reopen activates an existing window or
opens the initial one, and startup restores the normal windows that were open at
quit. A product package registers Crest for HTTP, HTTPS and HTML documents and
carries the app's Sparkle feed, so default-browser selection and update checks
use the existing app paths. Review packages keep neither, and their
default-browser affordance in Settings still reports the registration as
unavailable rather than hiding itself.

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

The process composition registers its native engine with each core session
using the v1 capability descriptor. Registration
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
sheet, whose paper settings scale the rendered pages. Reader and whole-page Apple
translation stay unavailable in Chromium and their menu items are absent rather
than dimmed; Chromium's page context menu translates a selection through Apple's
on-device translation instead. Developer commands open, switch and close DevTools on the
requested panel, except Network, which DevTools only exposes to Chromium's own
frontend. A docked inspector is mounted inside the page card it inspects, on the
dock side and at the size its own frontend asks for, so opening it adds no
window; undocking is a request for a window and Chromium opens one. Closing the
inspector by any route (its own close button, an undocked window close, the
page closing) clears the card's panel selection. Local documents open on both engines. File ▸ Open File… offers the
document kinds the registered engine reads, including its own archive format, and
the address route resolves `file://` URLs, absolute paths and home-relative paths
to the same URL. The core owns that resolution for every composition; the Swift
fallback it replaced has been removed. Local-file tabs have no
host, so the sync projection's scheme filter already keeps them on the device that
opened them.
Chromium's page context menu now offers Open Link in Split View through the same
shared store command the WebKit menu route uses.
Page creation and lifetime belong to the native composition and its engine
ports.

Space unlocking uses a process-local `SpaceAccessAuthority` in the .NET domain.
The native access controller presents Apple's authentication prompt and publishes
UI changes; it no longer owns an independent set of unlocked profiles. Grants
match both Space and profile identity. Only the current request may complete;
relocking cancels it, and a late result cannot consume a newer request. Scene
deactivation caused by the system prompt preserves that pending request. Explicit
locking always revokes access. These grants never enter checkpoints or sync.
The small C ABI uses fixed UUID bytes and synchronous calls, without JSON or a
message executor. Durable access-policy changes still use session commands, and
native page, credential and extension callers retain their existing access gates.
Each store family attaches that authority to its core session with
`crest_session_attach_access`, and a borrowed workspace inherits its source's.
The session authority then rejects a prepared command against a Space whose
stored policy requires authentication and holds no grant, with `space_locked`,
before any preparation runs. Raising a Space's protection, its deletion intents,
and retention or cleanup sweeps still apply while it is locked, because none of
them returns its tabs, folders, history or archive; removing protection is the
decision authentication guards, so it needs the grant like any other command.
The same rule covers the native value-edit path: a proposed session delta or
durable replacement that would change a locked Space's metadata, tabs, folders,
history, archive or splits, or remove it, is rejected with
`space_locked` before the revision is accepted, on the same allowlist. Sync
staging, merging and materialization commit as journal-bound replacements rather
than commands or value edits, so background convergence on a locked Space is
unaffected. Because the access policy has no modification stamp of its own on
the wire, materialization applies it monotonically toward protection: an
incoming record may raise protection, but may only remove it where this device
already holds the grant, and the local record wins on the next upload otherwise.

## Existing UI migration

`CrestNativeCore` and `CrestMobileNativeCore` build the existing platform entry
points, all original native views, and the current page infrastructure. Each has
an isolated bundle and profile.
Every composition routes domain operations through the packaged .NET library.
Tab opening, touching, duplication, closing, deletion, placement, filing,
renaming, residency preferences, folders, split groups, archive restoration and
automatic tab cleanup execute through the core. Address intent is a policy
operation, and history visits, history-range deletion and history and archive
retention are the `history.*` and `records.*` session commands.
Each store family has one `BrowserCoreSessionAuthority`. The .NET authority owns
committed session records and revisions, and Swift keeps an accepted read
projection for the existing UI. Commands carry arguments and what the window
shows, and never resend unchanged history or favicon bytes. Revision checks
reject stale commands. Transfers between families commit both graphs before either native
window reconciles its selection.

The core captures immutable checkpoints and encodes the session and per-Space
history on the native persistence worker. Editing can continue while an older
checkpoint is being saved. Persistent families store checkpoints through
`BrowserTransactionalSessionPersistence` in SQLite, after a one-time migration
from the legacy UserDefaults keys, and keep favicons in their side store.
Checkpoints hold browsing data only; see "Selection is window state" below.
Private and temporary families stay in memory.

### Selection is window state

Which Space a window shows and the tab it shows in each Space are UI state. The
core session holds Spaces, tabs, order, folders, splits and `lastActivatedAt`
timestamps, never what is on screen. `BrowserSession` and `BrowserSpace` carry no
selection; each window's `BrowserStoreSelection` is the only copy, persisted in
its `BrowserWindowState` record so relaunch returns to the same Space and tabs.
Views and page pools read a window's `BrowserPresentedSession` (the core's data
plus that window's selection), which is never encoded or sent to the core.

Commands send what the requesting window shows as read-only `view` context,
because some rules need it (a close falls back from the shown tab; cleanup keeps
the shown tab; a promotion inserts after it; a batch acts on the Space shown).
Every answer carries a `selection` hint (`spaceId`, per-Space `tabId`) that only
the issuing window applies; other windows reconcile their own selection against
what still exists. Showing a tab sends `tab.touch`, which only records
`lastActivatedAt`; showing a Space sends nothing. Launch cleanup runs the core's
`records.sweep` with `keepTabIds`, the tabs every stored window record shows,
before any window is on screen.

Older documents stored a session-level `selectedSpaceID` and per-Space
`selectedTabID`. They still load: the core's stored-format codec
(`StoredSessionCodec`) ignores the fields on the way in and never writes them,
and the native storage reads them once
(`BrowserLegacySessionSelection`) so the first window without its own record
adopts them; a record that predates captured Spaces folds them in and captures
from then on. Sync never carried selection and still does not.

### Commands and value edits

Live state ownership and checkpoint serialization belong to the core. Every
native edit is a semantic command on the family's authority. The only value
replacements left are incoming sync, which commits as a journal-bound
replacement, and the Debug-only test session setter.

The store's tab opening, touching, closing, deletion, current-tab clearing,
renaming and residency actions send commands directly to that authority.
Folder creation, appearance, renaming, collapse, deletion, moves and tab filing use the same path.
Requests contain arguments and what the window shows rather than an encoded Space.
The core prepares the edit against its owned records, the native adapter decodes
the resulting projection, and a revision-checked commit publishes both sides.
Abandoned preparations do not change state. Favicon bytes stay native, and
existing history and archive records do not cross the command boundary.

Single-tab duplication, same-Space moves, durable close, and split creation,
reordering, relocation and dissolution also execute against the authority's owned
records. Opening a link into a split is one atomic command, including any copies
of pinned or saved members. The core copies split metadata and returns asset
references; native adapters supply current page URL/title observations and prepare
opaque navigation history for accepted copies. Multi-selection batches use the
same owned authority. Their captured tab and folder
membership is revalidated before filing, copying, splitting, archiving, deleting
or transferring a selection. A batch reserves one session/journal commit; rejected
commands and canceled native close prompts publish no subset. Swift retains
selection presentation, current page observations and opaque copy history.
Native close confirmation precedes batch Archive/Delete, and the command checks
the selection again when confirmation returns. Batch deletion commits explicit
tombstones with tab removal, while archiving retains its non-deletion cause.

History visits and removal, archive restoration, automatic cleanup, retention and
split identity metadata now prepare against the authority's owned records. The
native caller sends intent and what its window shows, then applies only changed history
entries, removal references and tab or split projections. The core reads retention
preferences itself. Archive removals use positions so older repeated identities do
not cause an unexpired occurrence to be removed. Native favicon assets remain
attached when tabs move into or out of the archive, and other windows retain their
own selection during reconciliation.

Space creation, identity, appearance, preferences, default Space, saved-tab
disclosure, reordering and removal also use the authority's commands. Profile
identity is checked before editing; borrowed workspaces cannot change their source
profiles. The core enforces new private Space defaults and prevents removal of
the last Space. Native profile cleanup and authentication remain platform work.
A Space and its profile are one to one in every accepted document: a restored
session, value delta or import that would give two Spaces the same profile is
rejected as `duplicate_space_profile`, and checkpoint repair gives the colliding
Space a fresh profile instead of sharing another Space's browsing data.

Blank Windows and detached-tab windows request a borrowed workspace from the canonical core authority.
The core binds the source Space and profile identity, inherits its engine and
private-browsing registration, and creates empty local browsing collections.
Policy refresh reads the source authority directly and preserves local tabs,
folders, history, archive and split groups. A native snapshot cannot
create a borrower or replace its canonical policy. Prepared commands reject a
changed source revision; source deletion, replacement or release revokes access.
The Swift family publishes accepted projections and schedules native window
reconciliation. It no longer merges borrowed profile policy itself.

Quick Window and Peek promotion on Mac and mobile use the same transient
completion commands. The authority validates the source and destination profiles
against its current records and uses native authentication results to authorize
promotion. It creates the destination tab, hints the window to show it, preserves
insertion after the shown split group, and permits live-page adoption only within the same
Space/profile. The adapter performs the view transfer after commit; an unavailable
transfer falls back to loading the new tab. Empty Quick Windows only hint the
destination Space. Archive-on-dismiss uses the same domain collection and keeps
window selection unchanged, including when a retained snapshot was relocked.
Process-local completion receipts prevent a late dismissal or repeated promotion
from creating another record. Canceling a prepared storage reservation does not
consume the request. These receipts are not synced or restored. Page lifecycle
ownership is now split the same way on both engines: residency release planning,
tab dismissal and renderer-recovery decisions are core policy operations, while
the native adapters own page creation, the media residency veto, unload and
disposal.

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
the core's owned records. The core decides placement and split cleanup, and
answers each window's follow-up selection (the source window's fallback, the
destination window's moved tab). A workspace transfer reserves both revisions
until the persistent owner's session and sync journal are saved; cancellation
leaves both graphs unchanged. Private browsing and stale profile identities
cannot cross that boundary, and matching IDs cannot transfer between unrelated
profile owners. The native coordinator moves the existing page
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
pin limits and split membership, and applies history/archive retention.
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
one serial storage queue.

### Upgrading an installed session

The upgrade carries exactly two values: the installed release's
`UserDefaults` session core plus its per-Space history keys, and its sync
journal. Everything else keeps the identifier it already had and is read in
place, because the products share one identity. `ProductIdentity` resolves the
same `com.pauldavis.crest` defaults domain, the same
`Application Support/Crest` directory, the same keychain service namespace and
the same `iCloud.com.pauldavis.crest` container for the WebKit `Crest` target,
`CrestMobile`, and the Chromium composition that
`package-chromium-host.py --product` assembles from `CrestChromiumUIProduct`.
That packaged product rewrites `CFBundleIdentifier` to `com.pauldavis.crest`
and carries Crest's own CloudKit container key, and it omits
`CREST_REVIEW_BUILD`, so it takes the installed rather than the isolated launch
path and opens the same `ControlPlane/session.sqlite`, favicon store, tab-state
archive and download staging directory. None of these products is
App-Sandboxed; adding `com.apple.security.app-sandbox` to either side would
move every one of those paths into a container and strand the installed data,
so the product package must be signed with the Mac target's own entitlements.

`BrowserStore.migratedStorage` performs the carry and is the seam the upgrade
test drives with its own directory, defaults suite and favicon store.
`migrateIfNeeded` is a no-op once a checkpoint exists, so a later launch never
replaces accepted data with the retained legacy copy. A core the installed
release itself could not decode is copied aside by the legacy store, migrates
nothing, and requests a full cloud pull, so the disposable seed that stands in
is replaced by the Spaces CloudKit still holds instead of being published as
their deletion.

WebKit cookies and website data, WebKit extension packages and their granted
permissions, and WebKit tab interaction-state archives are engine-specific and
are not converted. The branch deletes none of them, so returning to the WebKit
app finds them intact; a Chromium tab without a usable archive falls back to
loading its URL. Physical-device validation and a real-account sync run against
installed Spaces are still outstanding. Startup stages restored local edits before cloud work,
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
New tab title and position edits use the same millisecond precision and native
date encoding as checkpoint repair. Receiving or restaging those edits must not
advance a record's logical clock merely because it crossed the native boundary.

Receiving an archive changes its local presentation to "synced" while retaining
the accepted record's original cause on upload. Archive display order follows
dates; it does not rewrite shared position tokens. Restaging after a cloud pull
preserves existing archive revisions and allocates positions only for new records.

Native record projections preserve additive encrypted payload fields through
CloudKit decoding, journal persistence and uploads. Core restaging carries those
fields forward using the supported payload vocabulary. Known optional fields
can still be cleared, and group/provider metadata follows member identity rather
than array position. Deleted members and tombstoned payloads are not resurrected.
New incompatible schemas still require a newer client.

Live cross-engine CloudKit validation must compare record identities and versions,
including fresh-profile adoption and repeated merges. An unreadable transactional
store opens native recovery UI before browser services or sync are constructed.
Successful launches preserve a complete SQLite checkpoint when session and journal
data are available. Restoring it validates every session part, retains the original
database and sidecars in a separate recovery directory, and uses an interruption
marker so a partial restore cannot become a fresh-install seed. A session saved by
a newer storage version requires an app update instead of offering rollback.
The core gives a restored journal a new local device identity while preserving
record versions and pending uploads. The matching CloudKit transport discards its
newer cursor and requires a complete merge before sending changes; account-change
confirmation remains enforced. Recovery checkpoints may predate recent local
edits, and the confirmation explains that limitation.
Native presentation codecs continue to normalize platform glyphs and branding values.

The value-level `BrowserSession` edit surface and its `crest_core_edit_session`,
`crest_session_commit` and `crest_session_commit_pair` exports are gone: every
native edit is a command on the family's authority, including launch cleanup and
retention. Commands exclude images, history and existing archive records. The
native projection keeps those records and presentation metadata, applies the
returned tab/folder values, and reconciles native pages through the existing
pools. The core's `BrowserTabCollection` owns the tab, folder and split
organization rules; profile access and page lifetime remain separate
responsibilities.

`crest_core_evaluate_policy` is a bounded, synchronous pure-function boundary:
it performs no I/O, engine operation, callback, or executor wait. It evaluates the
same `CrestCore.Domain` policies the session authority applies.
Record removal is not a policy call: the `records.sweep` and `history.*`
session commands apply the retention and range rules to the owned records.
Engine effects and the remaining command orchestration move behind the existing
store/page interfaces in coherent sections. The original UI, layout, and
interaction behavior remain the frontend.
The prototype `CrestControlPlane` and `CrestControlPlaneMobile` apps and their
Apple message transport have been removed. Product and review builds use the
original Crest UI. `CrestNativeCore` and `CrestMobileNativeCore` are isolated
compositions of that UI, not separate browser interfaces.

## Ownership and dependencies

| Module | Responsibility |
| --- | --- |
| `CrestCore.Domain` | Workspace, Space, profile identity, tab organization, history, archive and sync rules |
| `CrestCore.Application` | Accepted session ownership, semantic commands, storage reservations, sync projection and materialization |
| `CrestCore.Contracts` | Strict JSON parsing, adapter descriptors and protocol validation |
| `CrestCore.Native` | Exception-contained NativeAOT C exports and numeric handles |
| `CrestShared/Infrastructure/ControlPlane` | Original UI adapters, accepted session projections and checkpoint handles |
| `CrestShared/Infrastructure/Engines` | Registered native page, host-command and service contracts |
| `CrestNative/Apple/Composition` | Entitlements for isolated CloudKit review builds |
| `CrestEngines/Chromium/Apple` | Native SwiftUI composition and Objective-C engine port |
| `CrestEngines/Chromium/Overlay` | Chromium BrowserWindow, profiles, TabStripModel adoption and native observations |

Each store family owns one `NativeSessionAuthority`. Swift holds the accepted
projection and native assets; commands prepare against the core's current
revision. The native caller decodes the projection before committing it. Durable
commands reserve publication while the Apple storage adapter writes the matching
session and sync journal. Failed storage releases the reservation without
publishing a partial edit. Each window keeps its own selection when windows
reconcile with the accepted family state; only the issuing window applies a
command's selection hint.

The real WebKit composition uses `BrowserWebKitPageEngine` and the existing page
pools. The Chromium composition implements those same native ports through
`ChromiumNativePage`. The prototype `AppleWebKitAdapter`, `ChromiumAdapter`,
`CorePageRuntime` and `CoreTransport` wrappers have no role in either composition
and have been removed. Native rendering, request security and input remain with
the selected engine.

## Retired protocol runtime

The message-based `BrowserSessionKernel`, `BrowserKernel` and `CoreRuntime`, the
`Envelope`/`CoreOptions` wire types, the `crest_core_create` through
`crest_core_destroy` lifecycle exports and the kernel-only `BrowserWorkspace`
and `BrowserWindow` aggregates have been removed. Their former rules now belong to:

| Former kernel rule | Live owner |
| --- | --- |
| Session, window, Space, tab, folder and split editing | `NativeSessionAuthority` commands and `BrowserTabCollection` |
| One Space's tab, folder and split edit | `NativeSessionEditor`, called by the session commands |
| History, archive and retention sweeps | `NativeSessionMaintenance` and `NativeSessionAuthority.Records` |
| Address, search and link decisions | `SearchProviderCatalog`, `SearchPreferences`, `AddressResolution`, `LinkNavigationPolicy` via `NativePolicyEvaluator` |
| Space locking and device authentication | `SpaceAccessAuthority` behind `crest_access_*` |
| Cross-workspace transfer and borrowed workspaces | `NativeTabTransfer` and `NativeSessionAuthority.Borrowing`/`Transfer` |
| Sync projection, ordering, conflict and deletion | `NativeSyncAuthority` and the `crest_sync_*` entry points |
| Correlated completion invariants | Prepare/reserve/commit revisions on the session and sync handles |

Page creation, closure, residency operations and content blocking are native
engine work driven by the store and page interfaces; they are no longer modeled
as core messages. The decisions behind them are core policy operations: which
pages a memory squeeze may release, in what order and how many, what dismissing
a tab means, and when a terminated renderer stops reloading. The adapter keeps
the per-page veto for media playback, capture and Picture in Picture.
Downloads follow the same split on both engines: the process's one `CrestCore`
owns the download ledger behind `crest_app_*` (record phases, ordering,
acknowledgement and retention expiry), the `DownloadProgress` and
`DownloadRisk` queries answer progress and ETA and risk reasons, and the
`downloads.automatic` policy operation answers the automatic-download
throttle.
`BrowserDownloadCenter` sends engine download events as typed intents, owns
files, prompts and notices, and renders the records in `core.state`. Each
browsing mode shares one center across its windows. The ledger is not
persisted.
Credentials follow the same split. Policy operations decide what a form
observation means (fill offer, save candidate, save prompt, username hint), which
fill a field accepts, whether a candidate is still valid, which saved record is
the most recent for an account, and whether a save creates, updates or leaves a
record unchanged, as well as passkey access and system-password write-through.
They receive origins, dates, record identities and presence flags; passwords
never cross the boundary. The platform compares a candidate with the matched
record's stored secret and passes only the answer. The strong-password
operation returns a recipe, and the native layer draws the password from the
system's secure random source. Keychain storage, secrets and prompts stay
native; without a core answer nothing is captured, saved or filled.

Search follows the same split: the core's `SearchProviderCatalog` holds the
built-in engines and their templates, `SearchProvider` validates custom templates
and builds every results and suggestion URL, and custom-engine saves and removals
are Space commands that rewrite only the search fields of the stored preferences.
Swift keeps engine titles, icons and the editor's explanations. Automatic
translation rules live in the core's app preferences; `translation.rule` and
`translation.matches` answer them and `preferences.translation_rule` edits them.

Site permissions follow the same split. The process-local core ledger behind
`crest_permissions_*` owns every Space's saved and session choices, the
narrow-then-site-wide lookup, the combined camera and microphone rule, listing
order and which choices persist. `BrowserSitePermissionCenter` keeps its API
for the engines and the Privacy pane, supplies each Space's lock state, stores
the saved document the core returns under the existing
`crest.site-permissions.v1` key without reading it, and notifies observers.
Session choices never reach that document, and permissions are not synced. A
locked Space answers Ask, lists nothing and records nothing; resets still
apply. Secure-origin rules for location and hosted notifications, the
notification request action, automatic popups and the blocked-popup notice,
external schemes and consent, web-link and local-document acceptance, and HTTP
authentication handling, prompt labels and fixture trust are policy
operations; an unanswered permission is Ask, an unanswered URL or document is
refused and an unanswered scheme is blocked.

External links follow the same split. `links.route` decides where a link opened
from outside Crest goes (the first enabled route to an open Space, then the
Quick Window, most-recent or chosen Space preference), and `links.site` names the
site key a Quick Window remembers its Space under. Route creation, one-field
edits, reordering and removal are `links.route_*` operations, and
`links.space_removed` is the Space-deletion cascade: the deleted Space's routes,
chosen-Space preference and remembered sites go with it. The preferences stay in
their existing UserDefaults record, unchanged in format; the native store applies
and persists what the core returns, and an edit the core refuses or cannot answer
changes nothing. A link routed to a Space this process holds locked never raises
a prompt: `links.route` takes `lockedSpaceIDs` and substitutes a Quick Window on
the shown Space when it is unlocked, else the first unlocked one, answering no
Space when none can open; routing that cannot answer opens nothing. Quick Window archive lifetime, archive-on-dismissal and retargeting
(whether a move revises the request and remembers the site's Space) are
`quick_window.*` operations for the Mac window and the mobile overlay.

A borrowed workspace's Space commands are routed by one core rule,
`workspace.command_route`: identity, appearance, default Space, access,
browsing, search and credential preferences go to the Space it borrows from;
creating, removing, reordering Spaces and imports are refused there; everything
else is local. The borrowed authority enforces the same rule, rejecting a
source-owned command with `borrowed_profile_requires_owner`. The page surface
for a selected tab (`page.presentation`), the Balanced content-blocking rule
list (`content_blocking.rules`) and branding range rules (`branding.normalize`,
also applied by the `space.branding` command) are core policy; the crest's
heraldic vocabulary and its composition parameters stay native.

Window state follows the same split. Per-window selection and split column
shares stay device-local records in their existing format; policy operations
decide how a window reconciles with the session (which tab each Space shows,
which Space the window keeps, which column shares survive), whether captured
shares describe columns, whether a dragged tab may tear off, and the tab a
Space shows when its selection is gone. Folder depth, folder count and split
eligibility answers for menus are core commands prepared and released without
committing, and the `limits` operation reports every capacity the core
enforces so native surfaces keep no copies. The core never receives tab contents for these, only identities and
presence facts; without an answer a window keeps its state. Manual setup and
the import review keep their drafts native: the core admits draft edits
against the import's Space and pinned limits, gives new draft Spaces their
identity, reconciles drafts with Spaces changed elsewhere, suggests review
destinations, duplicates and pinned overflow through the `workspace.review`
query, and decides what finishing setup does. The workspace import rejects a
source whose split runs its repair would rewrite.

Shortcuts, launch and media follow it too. The core's `ShortcutCatalog` holds the
default chords, including ⌘1–⌘9 and ⌃1–⌃9 for numbered tab and Space selection,
and `ShortcutBindingPolicy` resolves the persisted overrides, reports conflicts
and revises the overrides when a binding applies; `BrowserShortcutStore` persists
the overrides in their existing format and caches the resolved chords for
dispatch, and a core that cannot answer reports a conflict rather than binding a
chord twice. Section grouping and search for the settings list stay in Swift.
`LaunchPolicy` decides from the platform's parsed launch flags whether a launch
is isolated, whether its web storage is ephemeral, whether installed-app UI
shows, and what the first window opens; without an answer a launch stays
isolated and opens the Start Page. Isolation is answered before any session
exists; the first window's destination is the session's `launch.plan` read,
which applies the saved startup preference the core owns. A tab opened from another is placed by the
`tab.open` command's `after` anchor, after the whole split of its origin.
`MediaSessionPolicy` arbitrates page media sessions identically for the WebKit
bridge and Chromium's native session: stale and retired reports, sibling
documents of a tab, the remembered-identity window, dismissal clearing, display
order and the Now Playing owner. `BrowserMediaSessionStore` keeps endpoints,
metadata, artwork and observation and applies the decisions; without an answer
it keeps its current state and order.
Behavior preferences are core state too. The persistent session carries one
`appPreferences` record beside its Spaces: the startup behavior, page
translation (offer, automatic, per-language rules), WebKit spell checking,
automatic Picture in Picture, what closing a saved tab does, the saved-tab
favicon return and Split View focus-follows-mouse. It persists with the
session checkpoint and changes only through `preferences.set`,
`preferences.translation_rule` and `preferences.import`; value edits and sync
replacement keep the owned record, private and borrowed workspaces refuse the
commands, and the first launch without a record imports the values the old
defaults keys held (the keys stay readable for older builds). The record is
device-local by design: the CloudKit record model has no app-level record,
three of these settings exist only on the Mac, and translation depends on the
language packs installed on each device. `BrowserAppPreferenceStore` is the
Swift projection that settings, translation, Picture in Picture, saved-tab and
Split View code read; a refused or unanswered edit leaves the value as it was.
WebKit reads its spelling default once per process, so launch reconciles that
engine copy with the record. Appearance preferences, link preferences,
shortcut overrides, sync choices and per-Space download locations stay native.
The C ABI is synchronous: `crest_session_*`, `crest_sync_*`, `crest_access_*`,
`crest_app_*`, `crest_permissions_*`, `crest_core_evaluate_policy` and
`crest_core_evaluate_sync`, declared in `CrestContracts/include/crest_core.h`
and `crest_app.h` and described in `CrestContracts/README.md`.
`CrestContracts/tests/native_abi.c` exercises the policy, access, app,
permissions and session entry points against the built library.

Once a store family attaches the access authority, `NativeSessionAuthority`
rejects a prepared command that would read or mutate a locked Space. It also
rejects a native value edit, such as the delta `crest_session_reserve_replacement`
reserves, that would change or remove a locked Space's records. Sync
replacements bound to a journal transaction are not gated, so background
convergence continues. `SpaceLockGateTests` covers commands, value edits,
sync, borrowing and profile sharing. The native controllers keep their own
gates, so the core gate is defence in depth rather than the only check.

The outstanding packages are itemized in [Engine abstraction
status](EngineAbstractionCompletion.md). Capability declarations must describe
the actual native adapter, not features available in stock Chrome.

### Typed Swift boundary

Swift names every core call with a typed operation. `BrowserSessionOperation`
lists session commands and reads, with the spellings of the core's
`SessionOperation.cs`. `BrowserPolicyOperation` lists pure policy calls
(`PolicyOperation.cs`), and `BrowserSyncOperation` lists sync journal
mutations, queries and evaluations (`NativeSyncOperation.cs`). App-wide
`preferences.*` commands use their own request model,
`BrowserAppPreferenceCommand`.

Requests and answers are Codable models. `BrowserSessionArguments` holds each
command's `arguments` member. `BrowserCoreNullable` encodes an absent value as
an explicit `null` for members the core always reads, and
`BrowserCoreOptional` reads a missing or mistyped answer member as `nil`.
Swift's typed identifiers such as `TabID` and `SpaceID` encode as
`{"rawValue":…}` records, so argument models carry plain `UUID`s instead.

`BrowserCoreErrorCode` names the rule an answer's `error` member reports. It
covers `BrowserRuleCodes.cs`, `NativeSyncDocumentErrorCodes.cs` and the
tab-batch rules. The set stays open: a code this build does not know still
decodes and falls to the caller's generic failure. On the core side, each
policy operation decodes its request into a typed record (`*PolicyRequests.cs`),
and each area keeps its wire codes in one `*Codes.cs` file.

A few spellings stay as they are for compatibility. The core parses
`TabBatchKind` in PascalCase. Sync document error codes are camelCase while
session rule codes are snake_case. Link routes carry lowercase UUID strings,
while other paths use the native encoder's spelling.

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
Physical-device validation of the upgrade is still outstanding.

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
`CrestCore`. After changing a record in `CrestCore.Contracts`, run
`Scripts/control-plane/generate-contracts.sh`; the lint script and the Apple
core build fail while the generated codecs and models are stale. See [the contract](../../CrestContracts/README.md) before adding a
command or provider. Frequent page observations use incremental tab projections
and stable observed row objects. Oversized structural snapshots stream in bounded
chunks and become visible only after complete digest validation. Creation limits
follow the existing import policy: 64 Spaces and 5,000 tabs per Space.
Session inputs and checkpoint parts are limited to 64 MiB, and pure sync
evaluation (`crest_core_evaluate_sync`) to 16 MiB. Large binary metadata must
move to a separate blob provider before either budget grows. Nobody has
validated full UI behavior at the import limits yet, or run the iOS build on a
physical device.

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
control-plane window it replaced has been removed.

The Chromium target uses the same .NET session authority and domain commands as
the WebKit targets. `ChromiumNativePage` creates a WebContents for the existing
`BrowserPage` and mounts its NSView inside the original page card. Navigation,
Back, Forward, reload, stop, title, URL and loading observations cross the native
host port. The existing pools still own page lifetimes and window presentation.
Engine effects do not pass through the core: page operations use the shared
native engine port, while portable session changes remain core-owned.

Chromium's native page context menu also works without a Views widget around the
page. It retains page and editing commands and adds Open Link in Peek for owned
HTTP/HTTPS pages. Chrome profile, app, Incognito, split and new-window destinations
are omitted until they have Crest-owned routing. Menu callbacks are bound to the source page and navigation
revision. The drag-start delegate runs after Chromium's enterprise drag policy;
ordinary URL drags can enter the existing AppKit link-pull controller. The
controller applies the current modifier preference, tracks the originating
window, and cancels on source changes, navigation, Escape or window deactivation.
Image, file, webpage-custom-data and selected-text drags keep Chromium's path;
Chromium's internal drag-tracking ID is permitted for ordinary link pulls. Pointer
samples stay native; promoting the resulting Peek uses the core completion
command.

`LinkNavigationPolicy` owns saved-site protection, Peek priority and modified-link
tab selection in the .NET domain. WebKit on Mac and mobile invokes that policy
once per navigation decision through the bounded native policy ABI. Chromium's
navigation throttle consults the same policy for user-activated top-level links
in owned pages. Off-site links from saved and pinned tabs open the native Peek
card; same-site links retain normal engine navigation. The saved-site boundary
ignores `www.` while keeping other subdomains distinct. Scripts, form submissions,
subframes, address-bar loads and redirects keep their engine paths. Deferred Peek
presentation is invalidated by source navigation, closure or reassignment.
Chromium carries the originating link event's Command, Option, Shift and middle
button state through its navigation request. The same core policy maps the user's
Peek modifier preference and selects foreground or background tabs. The adapter
changes tab disposition on the existing request, preserving Chromium's normal
navigation and popup adoption. A Peek request retains its verified referrer,
initiator, headers and source SiteInstance inside the engine. The native page port
passes only a one-shot token to a newly created page in the same profile and
window. The token expires on source navigation, closure, consumption or timeout;
it never enters persistence or sync. A stale token cannot fall back to a bare URL
load. Explicit download links keep Chromium's download path, and an unhandled
Option-click can use the originating frame's validated download operation.

The native page adapter propagates card viewport changes to Chromium during
attachment, navigation and resizing. Keyboard equivalents first reach the page;
unhandled equivalents then use Crest's AppKit menu and current responder.

Each Space uses a regular Chromium profile under the engine's user-data
directory. The product keeps it in `~/Library/Application Support/Crest/Chromium`
and uses Crest's installed session, sync and update state. A review package
requires an explicit `--user-data-dir`, and its native session uses its own
isolated defaults suite, separate from both production and the WebKit review
app. Packaging includes the original UI resources and the Sparkle dependency;
isolated startup disables updates and CloudKit by default. Chromium quit requests run native before-unload and download checks,
then flush native persistence before disposing pages.

The original private-window composition uses a separate in-memory Chromium
profile for each private Space. Closing that window releases its pages and
profile; reopening starts a fresh session. Popup adoption attaches the existing
WebContents to a core tab, preserving opener relationships and document state.
Unowned or stale popup offers are rejected.

Find uses an engine-neutral configuration, while Chromium supplies page search,
zoom and DevTools. A keyboard-triggered `_execute_action` popup anchors to the
extension's pinned tile, or to the control that opens the window's extension
list, rather than to wherever the pointer happens to be. Site Controls reads and changes Chromium's origin permissions;
permission requests use native sheets attached to the owning Crest window.
Extension actions use the active page's profile and Chromium's real action runner,
popup host, service workers and permission enforcement. Private windows only
expose extensions explicitly enabled for incognito use. Crest's original toolbar,
Site Controls grid, and install Space picker consume an observable native model;
Chromium owns action execution, installation, permissions, updates, and pin state.
Native Extensions settings provide Space-scoped management and copying, with a
link to Chromium's advanced manager. CRX verification precedes the native consent
review, and additional Space installations reuse only the explicitly reviewed
package and permission identity. A Chrome Web Store listing offers the same
install from its own button: a host-scoped script in an isolated world relabels
it for Crest, reports the installed state Chromium's registry holds for the
page's Space, and passes a click to the native review. The extension it can ask
for is the one the listing's address names, and private windows keep the store's
own behavior.

Extension action popups are hosted in a borderless child window of the Crest
window, placed below the control that opened them and kept on screen at an
edge. Chromium keeps the popup renderer and extension lifecycle. Internal browser addresses use
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

Whole-page translation and Reader are unavailable in Chromium by decision;
selection translation works. iCloud Passwords pairing in the signed product has
not been validated. Extension side panels are cards in the page row, opened from
the extension action's context menu, from an icon click, and from
`chrome.sidePanel.open()` and `close()`. The host dispatches extension keyboard
shortcuts for key equivalents Crest's own commands did not claim, and the
Extensions pane links to Chromium's shortcut page. Profile capabilities must
describe this integration before a feature is advertised as supported.

See [Chromium source preparation](../../CrestEngines/Chromium/README.md) for the
pinned build workflow.

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

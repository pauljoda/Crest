# Portable browser control plane

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

`crest_core_edit_session` receives one compact Space and returns an atomic edit.
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
| Chromium extensions | Engine-owned extension runtime | Native host integration; WebKit extension support is removed |
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

Space deletion saves an intent before disposing native profiles. Dependent
workspaces lose access and release their native pages first. Engine cleanup and
service cleanup have separate correlated acknowledgments; failure retains a
pending Space that can be retried. Completed tombstones remain in the checkpoint
and reject stale Space/profile records. WebKit implements deletion for its
isolated in-memory profiles. Chromium and production credential/sync providers
must establish their own cleanup contract before advertising deletion support.

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
runtime coordination and extension UI have been removed. Before-unload,
download and permission integration through the asynchronous adapter remain
unverified; their native browsing implementations remain in the actual app.
Chromium registration must likewise reflect the capabilities of the actual built
host, rather than assuming Chrome compatibility from the engine name.

## Build workflow

Install .NET SDK 10.0.201 or a servicing patch, Xcode, and XcodeGen. Regenerate
`Crest.xcodeproj` with `xcodegen generate` after changing `project.yml`.

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
and has no production iCloud or credential entitlements. Simulator execution does
not replace physical-device validation.

## Chromium host

The host overlay uses Chromium's browser startup, Browser and TabStripModel.
Its BrowserWindow implementation hosts native Crest windows and loads the
`CrestChromiumUI` framework after browser startup. The framework has no `@main`
and does not replace Chromium's application delegate. Chromium quit requests first run native before-unload handlers and the active-download
confirmation. Cancellation resets those native continuations. Accepted requests
then wait for the core’s save and native disposal sequence; a blocked save also
resets native quit preparation. This path still needs linked-host validation.

Each Space uses a regular profile under the explicitly supplied experimental
Chromium user-data directory. Private workspaces instead use distinct off-the-record contexts owned by the
source regular profile. They do not create a private profile directory. Chromium
excludes extensions from these additional off-the-record contexts; private
extension parity is not yet established. Profile leases remain alive
until the core disposes the engine. Native tabs move between per-profile,
per-window TabStripModels without replacing their renderer or navigation stack.
These host sources still require a linked browser and runtime validation before
their declared capabilities establish feature parity. The normal Crest UI and
production state are not yet cut over to this host.

See [Chromium source preparation](../../CrestEngines/Chromium/README.md) for the
pinned build workflow.

The engineering package is design input, not an implemented SDK. Its suggested
commit, publication, and report-storage workflow does not override repository
instructions or authorize external actions.

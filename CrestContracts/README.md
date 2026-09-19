# Experimental control-plane contract

The implemented C ABI is in `include/crest_core.h`. `CrestCore.Contracts.Protocol`
defines the current JSON contract. It parses bounded UTF-8 JSON directly and
builds JSON nodes without reflection. The application and domain have no native
engine references.

`crest_core_evaluate_policy` is a separate pure-function entry point for the
existing native store APIs during migration. Requests use `version: 1` and an
`operation`, with a 16 KiB input and 64 KiB output limit. It retains no state and
does not wait on the kernel. Address intent and history visit operations return
domain values. `records.expired` and `history.remove_range` accept at most 512
numeric timestamps in a consistent caller-chosen epoch and return zero-based
indices. Retention uses a strict age cutoff; explicit history ranges include
their start and exclude their end. Native callers apply the results only after
validating every batch, preserving their existing persistence and sync behavior.

This branch's protocol is experimental. It extends and changes the engineering
package's draft vocabulary, including flattened page identities and incremental UI
projections. The package's example messages are not compatibility fixtures for this
implementation. Do not advertise external ABI stability until the complete
contract and compatibility fixtures are ratified.

Every message contains `protocolVersion`, `sessionId`, `id`, `correlationId`,
`causationId`, `sender`, `recipient`, `sequence`, `kind`, `type`, and `payload`.
IDs are lowercase UUIDs. Sequences and page generations are positive decimal
strings, checked against the unsigned 64-bit range. Inbound sequences are
contiguous per registered sender. Duplicate message bytes with the same identity
are accepted without replaying effects while retained in the 4,096-message deduplication
window. Reusing an identity with changed bytes fails. Older evicted retries fail
their sequence check rather than executing again.

Register one `ui`, `engine`, and `platform` provider before starting. Required
capabilities are `pages`, `navigation`, and `surfaces`, at contract version 1 with
status `supported`. `partial`, `unavailable`, and `unverified` cannot satisfy a
required capability. Registration contains descriptor data only and never loads
code. The Swift composition root separately owns the actual handlers.

Configuration accepts `sessionId`, `protocolVersion`, `isolationMode`,
`queueByteLimit`, `messageByteLimit`, optional `persistSession`, and optional
`initialState`. Engine-profile isolation is `ephemeral` for memory-only website data
or `isolated` for a separate experimental profile directory. Neither permits using
the installed browser's profile. The native composition root enforces the storage
boundary. This is independent of saving browser descriptors. Persistent sessions also require a
`services` provider with the `session-storage` capability. The create configuration
may contain up to 16 MiB, including a restored checkpoint.
Messages are limited to 1 MiB; each native queue is limited to 8 MiB. Limits may
be lowered. Queue exhaustion returns `BUSY` before accepting a message. The
caller retains its bytes and identity while retrying. Oversized output fails the
session. Structural changes currently emit `ui.snapshot`; page observations emit
`ui.tab_changed` with the workspace ID, Space ID and one complete tab projection.
Both share one contiguous revision sequence. Swift keeps each observed tab object
stable while applying these updates. Oversized snapshots use `ui.snapshot_begin`,
ordered `ui.snapshot_chunk` frames, and `ui.snapshot_commit`, using `snapshotId`
as transfer identity. The metadata and validation rules match session streaming.
The UI publishes the new revision only after validating the complete payload.

`core.create_workspace` takes `windowId`, `sourceWorkspaceId`, `spaceId` and
`mode` (`private` or `borrowed`). It requires `workspace-profiles`. Commands can
include `workspaceId`; an existing window or page must belong to that workspace.
Native page identity determines observation routing even when a borrowed Space
has the same Space/profile identity as its source. Policy commands from borrowers
are restricted to their canonical source Space. `ui.snapshot` includes
`workspaceMode`; all workspace projections share one revision sequence.
`ui.workspace_removed` retires a workspace after native cleanup. Its browsing
records never enter another workspace’s storage projection.

`core.transfer_tab` moves one tab between workspaces with the same Space/profile
identity. It takes `sourceWorkspaceId`, `destinationWorkspaceId`, `spaceId`,
`tabId`, and the destination `windowId`. The source surface first acknowledges
detachment. `engine.reassign_page` then changes native ownership without replacing
the page, its generation, or its navigation stack. Its correlated
`engine.page_reassigned` reply commits record ownership; a
`engine.page_reassignment_failed` reply restores source presentation. Other
semantic commands wait in a bounded queue during the transfer. The move creates
no archive entry and detaches the moved tab from its previous split/folder. Native
feature tabs and dormant descriptors need no engine reassignment. Destination
surface presentation uses its normal lease; a later presentation failure leaves
the transferred record in its new workspace for retry. Transfers across different
profiles, including regular/private boundaries, are rejected.

On final workspace closure, outstanding native creation/closure drains before
`engine.release_workspace`. The effect identifies the workspace, its native
`windowIds`, and `releaseProfiles` owned by that workspace. Borrowers release no
profile. A correlated `engine.workspace_released` acknowledgement permits owner
release; the provider must dispose native pages, unadopted popups and surfaces
before returning it. Profiles must remain alive until their dependents finish.

`core.delete_space` requires `profile-deletion` and `space-data-deletion` providers.
It blocks access and moves affected windows to a surviving Space. The checkpoint
retains an intent identified by Space and profile; native cleanup starts only
after that intent is saved, current surface leases detach, pending page creation
drains, and borrowed workspaces acknowledge release. `engine.delete_profile` must
finish removal of that profile's pages and website data before acknowledging
`engine.profile_deleted`. `services.delete_space_data` then removes owned secrets
and other service records before `services.space_data_deleted`. Replies echo
workspace, Space, profile, effect cause and correlation. Either provider can
return its corresponding `_deletion_failed` observation. The Space stays visibly
pending until `core.retry_space_deletion` succeeds. Restart resumes from the
persisted intent; completed tombstones suppress stale records with the same Space
or profile identity. The last surviving Space and borrowed profiles cannot be
deleted. The isolated Apple service provider owns no vault or external records;
production services must implement their actual cleanup before declaring support.

`core.set_content_blocking` takes a Space, requesting window and `policy`
(`balanced` or `off`). The canonical profile owner persists this preference and
serializes `engine.apply_content_blocking` updates. Replies
`engine.content_blocking_applied` / `engine.content_blocking_failed` echo Space,
profile, cause and correlation. Later changes coalesce behind the pending update;
a failure remains visible and `core.retry_content_blocking` retries the desired
policy. Page creation carries `contentBlockingPolicy` and must install applicable
rules before reporting `engine.page_created`. Existing pages apply changes on the
next navigation or reload, without discarding unsaved forms. Deletion waits for
pending policy work. This feature requires the `content-blocking` capability.

`core.open_records` opens or selects a native `history` or `archive` tab.
`core.query_records` accepts `windowId`, `spaceId`, `kind`, `queryId`, optional
`query`, and a nonnegative `offset`. `ui.records` returns at most 50 matching
records plus the total and query identity. Oversized results use
`ui.records_begin` / `_chunk` / `_commit`, with `recordsId` identifying the
transfer and the query ID as its revision token. These read results do not change
the semantic projection revision or trigger persistence. The native UI rejects
superseded queries and clears records when a Space locks or its workspace closes.
History opening/deletion and archive restoration/deletion use core-owned record
IDs. Borrowed and private record queries remain scoped to their workspace.

`core.new_tab` reuses an available Start Page draft in the current Space.
Navigating that draft converts its existing tab identity to a web page.

UI commands currently cover window creation/closure, Space creation/renaming/
selection, web/native tab creation, selection/closure, navigation, native history
back/forward, reload/stop, tab renaming/residency, archive restoration, folder
creation/renaming/collapse/deletion, subtree movement, batch filing, placement,
duplication, split joining/removal, address resolution, search-provider selection
and custom-provider editing, save retry, and snapshots. `core.navigate_input`
resolves addresses and search queries using the selected Space's preferences;
the native address field submits text without owning that policy. Custom search
templates retain the existing HTTPS, placeholder, public-host and secret-field
restrictions. `core.bind_window_scene`
associates a native scene session with a durable window. Scene disconnection does
not close the window; UIKit scene-session discard does. `core.file_tabs` takes a `tabIds` array of UUID strings;
split members move together unless `detachSplitMembers` is true. Folder deletion
promotes its contents rather than closing pages. A web tab
is logical before its native page is created. Open completion means native
materialization completed; navigation state is observed separately. Navigation
command completion currently means the engine effect was dispatched, not that
the destination committed or finished loading.

`engine.adoption_requested` offers an already-created native page by an opaque
adoption ID, profile ID and optional source page ID. The core either emits
`engine.adopt_page` with a new logical identity or `engine.reject_adoption`.
Adoption uses the normal correlated creation completion but never emits a fresh
navigation: the native renderer, opener and request body remain intact. A native
close initiated outside the core is reported as `engine.page_destroyed`; a
core-requested close must still use its correlated completion. Internal browser
and extension URLs require the registered `internal-pages` capability.
`engine.reveal_requested` identifies a live page, such as a PiP or notification
source, and goes through the same core selection and ownership rules.

The engine returns page creation, metadata/history observations, close outcomes,
and native failures. Creation/close completions must match an outstanding effect,
its operation, tab, Space, page ID, and generation. Surface attachment has an
independent lease and acknowledgment. Cross-window selection waits for an
acknowledged source detach before committing ownership, then completes after the
destination acknowledges attachment. A destination failure restores the source
selection and its whole split group. `platform.assign_surface.pages` contains the
ordered native page identities for a window; `pageId` identifies its focused page.
`panes` includes native feature tabs and pages awaiting creation in the same order,
so each keeps its own presentation region.
One lease covers the complete group, which has only one window owner. Pixel buffers, pointer events, view objects,
and geometry do not enter the core.

Protected Spaces use `core.set_space_access`, `core.lock_space`, `core.lock_all`,
and `core.unlock_space`. The platform authenticates with the device owner through
a correlated `platform.authenticate_space` effect. Its result must match the
Space, profile, request and lock generation. Relocking cancels the request; a late
success cannot unlock a newer generation. Unlock state is never persisted. Locked
projections omit tab and folder content, while native lifecycle completions can
still drain safely. Unrecognized persisted access policies remain locked.

`core.set_retention` updates the Space’s cleanup and stored-record lifetimes.
`core.maintain_session` requests a sweep using the core clock; repeat pulses are
coalesced for one minute. Selected split members and unconnected scenes’ remembered
selections remain protected. Live pages close through their engine continuation,
and only successful closure archives them. Canceling that close renews the tab’s
activity timestamp. Download retention is stored for the download-policy adapter;
the current UI does not expose that setting before the ledger is connected.

Session writes carry a decimal `revision` and require a correlated
`services.session_saved` or `services.save_failed` observation. A small checkpoint
uses `services.save_session`. Larger checkpoints use `services.session_begin`,
ordered base64 `services.session_chunk` frames, and `services.session_commit`.
The begin effect specifies byte count, chunk count and SHA-256. Each following
frame names that effect as `saveId` and cause. Acknowledge the begin effect only
after all bytes are validated and durably written. Each frame fits the negotiated
message limit; normal output backpressure applies between frames.
Loading-only observations do not serialize the checkpoint. Durable changes are
coalesced behind the current write and compared with the last saved state.

During shutdown, accepted work drains and outstanding creation/close operations
and saves finish. A failed save emits `core.shutdown_blocked` and returns the core
to running so the UI can retry. Otherwise the core emits `engine.dispose_all`. The engine releases its native
objects and replies with `engine.stopped`, carrying the disposal message as its
cause and correlation. The reader drains until `STOPPED`, joins the stopped
executor, and destroys the handle. It never unloads the Native AOT image.

`tests/native_abi.c` is a native consumer of the actual shared library. It checks
buffer ownership, non-consuming size queries, invalid handles, and coordinated
shutdown. The managed suite covers browser ownership and transport rejection.

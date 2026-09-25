# Portable core contract

The implemented C ABI is in `include/crest_core.h`, `include/crest_app.h` and
`include/crest_engine.h`.

`crest_app.h` is the typed application API. Intents, changes, rejections,
queries and answers are the C# records in `CrestCore.Contracts`, and they cross
as a positional binary wire: lengths, counts, tags and enums are LEB128
varints, numbers are fixed-width little-endian, a GUID is 16 RFC 4122 bytes,
dates are f64 seconds since 2001, a byte string is its length followed by the
bytes, an optional is a presence byte and a union
is its root's tag followed by the type's fields. A record's `[Resolved]`
values, which the core computes from its fields, such as a tab's icon mode,
follow the fields; the core writes them and reads past them, and no stored or
synced format holds them. `crest_app_dispatch` answers
`CREST_OK` with the published changes or `CREST_REJECTED` with one rejection;
`crest_app_query` answers the same way. Both hand back a core-allocated
`crest_buffer_t` that the caller releases with `crest_buffer_free`.
`crest_app_create` takes the schema fingerprint and answers
`CREST_VERSION_MISMATCH` for any other. It also takes an encoded
`AppConfiguration`: with a storage directory the core owns `session.sqlite`
there, and a file it cannot use is a `CREST_REJECTED` rejection. The first
launch over an empty file sends `AdoptLegacySession` with the installed
release's raw defaults values, and the core carries them in; `crest_app_restore`
puts the recovery checkpoint back while no app has the directory open. Changes the
core starts itself, such as `Saved` and `StorageFailed`, wait for
`crest_app_drain` after a payload-free `crest_app_set_wake` callback. Everything but the header itself is
generated: run `Scripts/control-plane/generate-contracts.sh` after changing a
contract record to rewrite the core's codec, the Swift models and codec, and
`include/crest_contracts.h` with the tags and the fingerprint. Source code
never spells a wire tag.

`crest_engine.h` is the engine contract. An engine binding registers with an
app through `crest_engine_register`, passing the engine contract's own
fingerprint, an encoded `EngineRegistration` (its kind, the capabilities it
supports, whether new pages open on it) and a function table the core copies.
Every engine must support the required capabilities and one engine is the
default. The core runs `EngineCommand`s (`CreatePage`, `LoadPage`, `ClosePage`)
through the table's `run`, in order, never while it holds a lock and never on
the stack of the report that caused them. The binding reports `EngineEvent`s
(`PageCreated`, `PageCreationFailed`, `PageClosed`, the navigation events and
`PageStateChanged`) with `crest_engine_report`, which never refuses one. A
binding reports a page's `PageSnapshot` at most once per turn and only when it
changed; the core keeps it with the page's failure as `PageLiveState` and
publishes `PageChanged` only when that differs. The engine fingerprint covers only the engine roots and the
registration, so an edit elsewhere in the contracts leaves it unchanged. The
`OpenPage`, `MovePage`, `ReleasePage`, `Navigate` and `LeavePageFailure`
intents on `crest_app_*` own page identity and loads: which tab or transient
request owns each page, which engine hosts it, what an address the person
typed resolves to, and the lock, deletion and one-page-per-tab rules. Pages are
never saved or synced.

`CrestCore.Contracts.Protocol` defines the current JSON contract. It parses bounded UTF-8 JSON directly and
builds JSON nodes without reflection. The application and domain have no native
engine references.

The native Crest apps use the `crest_app_*` entry points, plus
`crest_core_evaluate_policy`. The cloud transport sends its
`CloudSyncIntent`s through `crest_app_dispatch` from its own thread, and asks
`PendingUploads`, `RecordsToUpload` and `CloudComparison` through
`crest_app_query`; what a cloud intent changed arrives in the next
`crest_app_drain`. Each `SyncRecord` carries its payload or tombstone exactly
as CloudKit stores it, with the schema it needs; the core reads and writes
those bodies, and a record-taking intent answers `SyncRecordsSkipped` for the
records it could not read or that a newer build wrote.
`crest_app_settle_sync` waits off the UI thread for the sync stages already
requested.
The session holds browsing data only; which Space and tab a window shows is the
device's window state. Workspaces open and close through `crest_app_dispatch`:
`OpenWorkspace` opens the session the core keeps in its file, a private one from
its template, or a seed in the stored format for launches without a file;
`BorrowSpace` opens a workspace over another's Space; `CloseWorkspace` closes one
and its borrowers. The core gives each its identity in `WorkspaceOpened`, which
every session intent names. Only the file's workspace saves and syncs.
Session intents name
the window that issued them; when an intent commits, the device moves that
window to what the intent chose, repairs every other window of that workspace,
and publishes `WindowChanged` for each window that changed. Imports
(`ImportSpaces`, `ImportReviewedSpaces`, `ApplyManualSetup`) are intents too,
and `ImportPreview`, `ImportReviewSuggestions` and `ImportReviewAnalysis` answer
the review a person edits before one. The session file never stores a selection; a stored document with the
older session-level `selectedSpaceID` and per-Space `selectedTabID` still loads,
gives its tabs to a window without a record during that launch, and loses them
at the next save. `SweepExpiredRecords` keeps every tab an open window or a
saved window's record shows.
Process-local Space unlock grants belong to the app: `BeginUnlockingSpace`,
`FinishUnlockingSpace`, `LockSpace` and `LockAllSpaces` go through
`crest_app_dispatch`, and each publishes `SpaceLockChanged` for the Space
profiles it changed. The platform presents the authentication prompt and
answers with its result; the core accepts only the pending request for the
exact Space/profile identity, and relocking cancels it. Grants are never
persisted or synced. The device attaches the grants to every session it shows,
which then refuses intents with `SpaceLocked`; cloud sync intents are not
gated.

The asynchronous message-based kernel (`crest_core_create` through
`crest_core_destroy`, envelopes and adapter message routing) has been retired.
Its browsing, records, deletion, transfer, residency and content-blocking rules
are now owned by the synchronous session, sync, app and policy entry points
above. `Documentation/Architecture/ControlPlane.md` describes that live path.
`CrestCore.Contracts.Protocol` retains the shared JSON parsing helpers.

`crest_core_evaluate_policy` is a separate pure-function entry point for the
native store APIs. Requests use `version: 1` and an
`operation`, with a 16 KiB input and 64 KiB output limit. It retains no state or
executor. Address intent returns domain values. History visits, range removal
and retention are session edits (the `history.visit` command and the
`RemoveHistoryRange` and `SweepExpiredRecords` intents), not policy
operations; retention uses a strict age cutoff and explicit history ranges
include their start and exclude their end. `limits` answers every capacity the
core enforces (pinned tabs, folders and depth, history entries, split members,
brand colors, crest palette, Spaces, tabs per Space, sync records).
`address.intent` and `search.url` name the engine as `{"id":"google"}` for a
built-in or a `custom:<uuid>` identity with its stored templates; the core owns the
built-in catalog, template validation and query encoding, and a stored custom
engine that no longer validates resolves to Google. `search.custom_providers`
applies the restore rule to stored engines. `translation.rule` and `translation.matches`
answer automatic page-translation choices in their persisted native shape. The
`AddSearchEngine`, `UpdateSearchEngine`, `RemoveSearchEngine` and
`SelectSearchEngine` intents edit a Space's engines and its choice, refusing with
`DuplicateSearchEngineName`, `SearchEngineLimitReached`, `InvalidSearchEngine` or
`UnknownSearchEngine`. A Space's choice is a `BuiltInSearchEngine` or a custom
engine's identity, stored as the built-in's name or `custom:<uuid>`.

The downloads area of `crest_app_*` owns the process's download ledger: record
phases and their transitions, newest-first ordering, badge acknowledgement and
retention expiry (the shortest retention among Spaces sharing a profile). It is
never persisted or synced. Each download intent answers `DownloadUpdated` with
the record and its newest-first position, or `DownloadsRemoved`; an event that
does not apply to a record's phase answers no changes. Engines keep reporting
download events and the native center forwards them as intents. The
`DownloadProgress` query answers transfer telemetry and ETA with the estimator
state to send with the next sample, and `DownloadRisk` answers risk reasons and
whether the person must confirm; the platform supplies only its
file-system-safe filename and type registry facts. The `downloads.automatic`
policy operation still answers the automatic-download throttle, because it
reads a site-permission decision.

The credentials area of `crest_app_*` answers typed queries that carry no
credential values. `CredentialCapture` takes a form observation as its event,
origins and presence flags; `MostRecentCredential` and `CredentialSaveMatch`
take record identities, dates and, for matching, usernames; `CredentialSave`
takes the platform's yes-or-no comparison against the stored secret.
`StrongPassword` answers a length and character groups, and the platform
generates the password itself. `CredentialFill`, `CredentialSaveCheck`,
`PasskeyAccess`, `SystemPasswordWriteThrough` and `SystemPasswordOffer` answer
the remaining fill, save, passkey and system Passwords rules. Record batches
hold at most 64 entries; callers reduce longer lists batch by batch.

Site permission choices are device state. `DecideSitePermission`,
`ResetSitePermission` and `ResetSpacePermissions` change them, and
`SitePermissionsChanged` carries a Space's kept choices in listing order with
what the change covered. `SiteDecision` and `CaptureDecision` answer a request:
the narrow-then-site-wide lookup and the combined camera and microphone rule,
with session choices first. The device store keeps the persistent session's
choices beside the session, never in it; private and other Spaces' choices,
and session choices, live in memory, and nothing here syncs. A locked Space
answers Ask and refuses writes, while resets still apply. `AdoptSitePermissions`
carries the document earlier releases kept under `crest.site-permissions.v1`
into the store once.
The pure `geolocation.origin`, `notifications.origin`,
`notifications.permission_request`, `popups.notice`, `external.url`,
`external.local_document`, `external.scheme`, `authentication.handling`,
`authentication.source_label` and `authentication.fixture_trust` operations
answer the origin, scheme, popup-notice and HTTP authentication rules. What a
saved decision means (whether it grants, blocks or asks) travels with the
generated `SitePermissionDecision`, so no operation answers it. URLs arrive as the platform
parser's facts; every caller refuses, blocks or asks when it gets no answer.

The `ExternalLinkRoute` query takes the link preferences routing reads and the
Spaces this process holds locked: a link routed to a locked Space answers a Quick
Window on an unlocked one with `SubstitutesForLockedSpace`, or no Space when none
can take it. `QuickWindowSite` answers the site key a Quick Window remembers its
Space under. The `links.route_*` operations carry link routes as
`{"id","isEnabled","match","pattern","destinationSpaceID"}` with lowercase UUID
strings. Route edits answer
the edited route or `{"error":code}`, reorders and removals answer the route
order, and `links.space_removed` answers what a deleted Space leaves behind.
`quick_window.*` answer archive lifetime, archive-on-dismissal and retargeting;
`page.presentation` and `branding.normalize` answer page surfaces and branding
range rules, and the `BalancedProtectionRules` query answers the Balanced rule
list.

Window state is device-local and never enters the session. The
`OpenWindow`, `CloseWindow`, `ShowSpace`, `ShowTab`, `DismissShownTab`,
`ResizeSplitColumns` and one-time `AdoptWindowRecords` intents on `crest_app_*`
own it; windows over the persistent session keep their records in device tables
beside the session, sixteen at most. Showing a tab records its
`lastActivatedAt` as a change of its own and publishes `TabsChanged`. Each
session attached to the device publishes `WorkspaceOpened`, what every
accepted state changed, and `WorkspaceClosed`, keyed by workspace, and an
intent answers the pending batch before its own changes. The
`CanTearOff` query decides whether a dragged tab may leave its window, and
`FallbackTab` answers the tab a draft Space shows first. `setup.space`, `setup.tab` and `setup.reconcile`
admit manual-setup draft edits against the import's Space and pinned limits
and follow Spaces changed elsewhere; `onboarding.completion` and
`onboarding.guide` decide what finishing setup does. The import review reads
whole Spaces: `ImportReviewSuggestions` suggests each imported Space's
destination, duplicates and default tabs, and `ImportReviewAnalysis` reports,
for the choices a person made, duplicates, matched destination tabs and pinned
overflow. The
workspace import rejects a source whose split runs its repair would rewrite.

Shortcut choices are device state too. `AssignShortcut` binds keys to a
command and is refused with `ShortcutInUse` naming the offered commands that
already answer to them; `ReassignShortcut` takes them from those commands;
`UnassignShortcut`, `ResetShortcut` and `ResetShortcuts` clear or forget
choices. `ShortcutsChanged` carries every offered command's keys, and the
commands offered are those the default engine can perform. `AdoptShortcuts`
carries the choices earlier releases kept under `crest.keyboard-shortcuts.v1`
into the device store once, keeping those for commands the core does not know.
The `NumberedSelections` query maps each numbered command to the zero-based
tab or Space it reaches for the given counts. `AppConfiguration` names the
device's platform, whose defaults the shortcut rules read.
`launch.plan` takes the platform's parsed launch flags and whether first-run
setup owns the first window, and answers isolation, ephemeral profile storage,
installed-app presentation and the startup behavior for a person who never
chose. The `LaunchPlan` query answers the same for the persistent workspace,
with the startup preference it keeps.

The persistent session's `appPreferences` record holds the app-wide behavior
preferences (`startupBehavior`, `offersTranslation`, `automaticallyTranslates`,
`translationRules`, `checksSpelling`, `automaticallyEntersPictureInPicture`,
`savedTabClosePolicy`, `savedTabFaviconReturnsToSavedURL`,
`splitFocusFollowsMouse`), using the raw values the native settings stored.
`SetAppPreferences` sets the record, `SetTranslationRule` edits one source
language's rule, and `ImportAppPreferences` takes the old defaults values
(translation rules as their stored JSON text), applied only while the session
has no record. Private and borrowed workspaces refuse them with
`PersistentWorkspaceRequired`. Value deltas and sync replacement never change
the record, and sync never uploads it.
`media.session_event` decides what one sequenced page media-session report does
(ignored, retired, withdrawn or published, with its ordinal, sibling supersession,
identity-window eviction and dismissal clearing) and `media.arbitrate` orders at
most 64 published sessions and names the Now Playing owner; neither carries
metadata or artwork. The `OpenTab` intent names `AfterTabId`, a tab the new
tab opens after and outside the split of, instead of an explicit index.

This branch's contract is experimental. Do not advertise external ABI stability
until the complete contract and compatibility fixtures are ratified.

`tests/native_abi.c` is a native consumer of the actual shared library. It
exercises the policy, app, engine and session entry points,
checking buffer
ownership, non-consuming size probes, stale commands and invalid handles. The
managed suite covers the session, sync and domain rules.

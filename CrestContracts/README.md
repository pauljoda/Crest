# Portable core contract

The implemented C ABI is in `include/crest_core.h` and `include/crest_app.h`.

`crest_app.h` is the typed application API. Intents, changes, rejections,
queries and answers are the C# records in `CrestCore.Contracts`, and they cross
as a positional binary wire: lengths, counts, tags and enums are LEB128
varints, numbers are fixed-width little-endian, a GUID is 16 RFC 4122 bytes,
dates are f64 seconds since 2001, an optional is a presence byte and a union
is its root's tag followed by the type's fields. `crest_app_dispatch` answers
`CREST_OK` with the published changes or `CREST_REJECTED` with one rejection;
`crest_app_query` answers the same way. Both hand back a core-allocated
`crest_buffer_t` that the caller releases with `crest_buffer_free`.
`crest_app_create` takes the schema fingerprint and answers
`CREST_VERSION_MISMATCH` for any other. It also takes an encoded
`AppConfiguration`: with a storage directory the core owns `session.sqlite`
there, and a file it cannot use is a `CREST_REJECTED` rejection. Changes the
core starts itself, such as `Saved` and `StorageFailed`, wait for
`crest_app_drain` after a payload-free `crest_app_set_wake` callback. Everything but the header itself is
generated: run `Scripts/control-plane/generate-contracts.sh` after changing a
contract record to rewrite the core's codec, the Swift models and codec, and
`include/crest_contracts.h` with the tags and the fingerprint. Source code
never spells a wire tag. `CrestCore.Contracts.Protocol`
defines the current JSON contract. It parses bounded UTF-8 JSON directly and
builds JSON nodes without reflection. The application and domain have no native
engine references.

The native Crest apps use the `crest_session_*`, `crest_sync_*`,
`crest_access_*`, `crest_app_*` and `crest_permissions_*` entry points,
plus `crest_core_evaluate_policy` and `crest_core_evaluate_sync`.
The session holds browsing data only; which Space and tab a window shows is
window state. Session commands take what the requesting window shows as
read-only `view` context (`{"spaceId", "tabs": [{"spaceId", "tabId"}]}`) and answer
with a `selection` hint of the same shape that only that window applies.
`tab.touch` records `lastActivatedAt` and nothing else. The session file never
stores a selection; a stored document with the older session-level
`selectedSpaceID` and per-Space `selectedTabID` still loads, hands them to the
launch window once through `crest_app_session`, and loses them at the next save. `records.sweep` accepts `keepTabIds`,
the tabs stored window records show, for launch cleanup.
`crest_access_*` owns process-local Space unlock grants, shared by the native
desktop and mobile access controllers. The platform supplies device-authentication
results; the core accepts only the current request for the exact Space/profile
identity. Relocking invalidates pending results. Grants are never persisted or
synced. This small synchronous boundary uses 16-byte UUIDs and integer results,
without message serialization or an executor wait. A session attached with
`crest_session_attach_access` rejects commands and native value edits
(`crest_session_replace_durably` without a journal) that would reach a locked Space with
`space_locked`; journal-bound sync replacements are not gated. Native UI, page,
credential and extension callers continue to consult the same access controller.

The asynchronous message-based kernel (`crest_core_create` through
`crest_core_destroy`, envelopes and adapter message routing) has been retired.
Its browsing, records, deletion, transfer, residency and content-blocking rules
are now owned by the synchronous session, sync, access and policy entry points
above. `Documentation/Architecture/ControlPlane.md` describes that live path.
`CrestCore.Contracts.Protocol` retains the shared JSON parsing helpers and the
v1 capability descriptor used by `crest_session_register_engine`.

`crest_core_evaluate_policy` is a separate pure-function entry point for the
native store APIs. Requests use `version: 1` and an
`operation`, with a 16 KiB input and 64 KiB output limit. It retains no state or
executor. Address intent returns domain values. History visits, range removal
and retention are session commands (`history.*`, `records.sweep`), not policy
operations; retention uses a strict age cutoff and explicit history ranges
include their start and exclude their end. `limits` answers every capacity the
core enforces (pinned tabs, folders and depth, history entries, split members,
brand colors, crest palette, Spaces, tabs per Space, sync records).
`address.intent` and `search.url` name the engine as `{"id":"google"}` for a
built-in or a `custom:<uuid>` identity with its stored templates; the core owns the
built-in catalog, template validation and query encoding, and a stored custom
engine that no longer validates resolves to Google. The typed
`CustomSearchEngineAdmission` query answers the engine Crest would save or
refuses it with the rule it breaks, and `search.custom_providers` applies the
restore rule to stored engines. `translation.rule` and `translation.matches`
answer automatic page-translation choices in their persisted native shape. Custom-engine saves and removals are the
`space.search_provider.upsert` and `space.search_provider.remove` session commands.

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

`crest_permissions_*` owns one process-local site permission ledger per native
permission center: per-Space saved and session choices, the narrow-then-site-wide
lookup, the combined camera and microphone rule, listing order and which
choices persist. `load` restores the saved document exactly as the native store
has always written it under `crest.site-permissions.v1`; `set`, `reset_record`,
`reset_space` and `reset_session` answer `applied`, the complete saved
`document` when it must be written again, and the `changes` observers receive.
Session choices never appear in the document, and permissions are not synced.
Every question and write carries the Space's `locked` state: a locked Space
answers `ask`, lists nothing and records nothing, while resets still apply.
The pure `geolocation.origin`, `notifications.origin`,
`notifications.permission_request`, `popups.automatic`, `popups.notice`,
`external.url`, `external.local_document`, `external.scheme`,
`external.consent`, `authentication.handling`, `authentication.source_label`
and `authentication.fixture_trust` operations answer the origin, scheme,
popup-notice and HTTP authentication rules. URLs arrive as the platform
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
`workspace.command_route` answers `local`, `source` or `rejected` for a session
command issued from an owned or borrowed workspace.

Window state is device-local and never enters the session. `window.repair`
takes the window's selected Space, whether the window records captured Spaces,
one presence-fact entry per session Space (at most 64) and the window's stored
split layouts with their live member counts (at most 64); it returns the
selected Space, one `window`/`first`/`none` tab choice per Space, the layouts to
keep and the captured Spaces. `window.split_layout`
validates and normalizes captured column shares, `window.tear_off` decides
whether a dragged tab may leave its window, and `tabs.selection_fallback`
returns the tab a Space shows when its selection is gone. `setup.space`, `setup.tab` and `setup.reconcile`
admit manual-setup draft edits against the import's Space and pinned limits
and follow Spaces changed elsewhere; `onboarding.completion` and
`onboarding.guide` decide what finishing setup does. The import review, which
reads whole Spaces, is the `workspace.review` query on the
`crest_sync_query_*` path beside `workspace.preview`: without `choices` it
suggests each imported Space's destination, duplicates and default tabs; with
them it reports duplicates, matched destination tabs and pinned overflow. The
workspace import rejects a source whose split runs its repair would rewrite.

`shortcuts.bindings` resolves the platform's offered `commands` (at most 128)
against the person's `overrides` (a command name to a chord, or null when left
unassigned) and returns each command's live chord and catalog default; chords use
the native persisted shape `{"key":{"character":"n"},"modifiers":1}`, and
overrides for commands the core does not know are carried through verbatim.
`shortcuts.assign` binds or clears one command and returns `assigned` with the
complete revised overrides, `conflict` with the offered commands already holding
the chord, or `invalid`. `shortcuts.numbered_selection` maps each numbered
selection command to the zero-based tab or Space it reaches for the given counts.
`launch.plan` takes the platform's parsed launch flags and whether first-run
setup owns the first window, and answers isolation, ephemeral profile storage,
installed-app presentation and the startup behavior for a person who never
chose. The same request as a session command reads the saved startup
preference; the caller releases it without committing.

The persistent session's `appPreferences` record holds the app-wide behavior
preferences (`startupBehavior`, `offersTranslation`, `automaticallyTranslates`,
`translationRules`, `checksSpelling`, `automaticallyEntersPictureInPicture`,
`savedTabClosePolicy`, `savedTabFaviconReturnsToSavedURL`,
`splitFocusFollowsMouse`), using the raw values the native settings stored.
`preferences.set` takes `preference` and `value`,
`preferences.translation_rule` takes `sourceID`, `targetID` and `isEnabled`,
and `preferences.import` takes `legacy`, the old defaults values (translation
rules as their stored JSON text), applied only while the session has no record.
Each answers `{"preferences": record}`. Unknown names and ill-typed values are
`unknown_preference` and `invalid_preference_value`; private and borrowed
workspaces refuse the commands. Value deltas and sync replacement never change
the record, and sync never uploads it.
`media.session_event` decides what one sequenced page media-session report does
(ignored, retired, withdrawn or published, with its ordinal, sibling supersession,
identity-window eviction and dismissal clearing) and `media.arbitrate` orders at
most 64 published sessions and names the Now Playing owner; neither carries
metadata or artwork. The `tab.open` session edit accepts `after`, a tab the new
tab opens after and outside the split of, instead of an explicit `index`.

This branch's contract is experimental. Do not advertise external ABI stability
until the complete contract and compatibility fixtures are ratified.

`tests/native_abi.c` is a native consumer of the actual shared library. It
exercises the policy, access, app, permissions and session entry points,
checking buffer
ownership, non-consuming size probes, stale revisions and invalid handles. The
managed suite covers the session, sync and domain rules.

# Portable core contract

The implemented C ABI is in `include/crest_core.h`. `CrestCore.Contracts.Protocol`
defines the current JSON contract. It parses bounded UTF-8 JSON directly and
builds JSON nodes without reflection. The application and domain have no native
engine references.

The native Crest apps use the `crest_session_*`, sync and policy entry points.
`crest_access_*` owns process-local Space unlock grants, shared by the native
desktop and mobile access controllers. The platform supplies device-authentication
results; the core accepts only the current request for the exact Space/profile
identity. Relocking invalidates pending results. Grants are never persisted or
synced. This small synchronous boundary uses 16-byte UUIDs and integer results,
without message serialization or an executor wait. Native UI, page, credential
and extension callers continue to consult the same access controller.

The asynchronous message-based kernel (`crest_core_create` through
`crest_core_destroy`, envelopes and adapter message routing) has been retired.
Its browsing, records, deletion, transfer, residency and content-blocking rules
are now owned by the synchronous session, sync, access and policy entry points
above. `Documentation/Architecture/ControlPlane.md` describes that live path.
`CrestCore.Contracts.Protocol` retains the shared JSON parsing helpers and the
v1 capability descriptor used by `crest_session_register_engine`.

`crest_core_evaluate_policy` is a separate pure-function entry point for the
existing native store APIs during migration. Requests use `version: 1` and an
`operation`, with a 16 KiB input and 64 KiB output limit. It retains no state or
executor. Address intent and history visit operations return domain values.
`records.expired` and `history.remove_range` accept at most 512
numeric timestamps in a consistent caller-chosen epoch and return zero-based
indices. Retention uses a strict age cutoff; explicit history ranges include
their start and exclude their end. Native callers apply the results only after
validating every batch, preserving their existing persistence and sync behavior.

`crest_downloads_*` owns one process-local download ledger per native download
center: record states and their transitions, newest-first ordering, badge
acknowledgement and retention expiry (the shortest retention among Spaces sharing
a profile). It is never persisted or synced. Each v1 JSON `command` runs once and
leaves a delta (`applied`, changed `items` with their indices, `removed`
identities) for `crest_downloads_read`. Engines keep reporting download events
and the native center forwards them; events that do not apply to a record's
state are reported as not applied. The pure `downloads.progress`,
`downloads.risk` and `downloads.automatic` policy operations answer transfer
telemetry and ETA, risk reasons and confirmation, and the automatic-download
throttle. The platform supplies only its file-system-safe filename and type
registry facts for risk.

This branch's contract is experimental. Do not advertise external ABI stability
until the complete contract and compatibility fixtures are ratified.

`tests/native_abi.c` is a native consumer of the actual shared library. It
exercises the live policy, access and session entry points, checking buffer
ownership, non-consuming size probes, stale revisions and invalid handles. The
managed suite covers the session, sync and domain rules.

#ifndef CREST_CORE_H
#define CREST_CORE_H

/* Experimental ABI v1. Implementation: CrestCore/src/CrestCore.Native.
 * All strings/messages are length-delimited UTF-8, not NUL-terminated.
 * No caller may unload the Native AOT library before process exit.
 */
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#  if defined(CREST_CORE_BUILD)
#    define CREST_API __declspec(dllexport)
#  else
#    define CREST_API __declspec(dllimport)
#  endif
#  define CREST_CALL __cdecl
#else
#  define CREST_API __attribute__((visibility("default")))
#  define CREST_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define CREST_ABI_VERSION 1u

typedef int32_t crest_status_t;

#define CREST_OK                ((crest_status_t)0)
#define CREST_EMPTY             ((crest_status_t)1)
#define CREST_BUFFER_TOO_SMALL  ((crest_status_t)2)
#define CREST_TIMEOUT           ((crest_status_t)3)
#define CREST_STOPPED           ((crest_status_t)4)
#define CREST_BUSY              ((crest_status_t)5)
#define CREST_INVALID_ARGUMENT  ((crest_status_t)-1)
#define CREST_VERSION_MISMATCH  ((crest_status_t)-2)
#define CREST_INVALID_STATE     ((crest_status_t)-3)
#define CREST_INVALID_HANDLE    ((crest_status_t)-4)
#define CREST_INVALID_MESSAGE   ((crest_status_t)-5)
#define CREST_INTERNAL_ERROR    ((crest_status_t)-6)
#define CREST_LIMIT_EXCEEDED    ((crest_status_t)-7)
/* A durable save to the app's session file failed; nothing was published. */
#define CREST_STORAGE_FAILED    ((crest_status_t)-8)

/* Returns the ABI major supported by this image. */
CREST_API uint32_t CREST_CALL crest_core_abi_version(void);

/* Process-local site permission ledger: per-Space saved and session choices,
 * their lookup, ordering and persistence rules. The native store keeps the
 * saved document the ledger returns; session choices are never in it and
 * nothing here is synced. Apply runs one v1 JSON command exactly once (input
 * <= 4 MiB) and reports the size of its JSON answer; read copies that answer,
 * with a non-consuming BUFFER_TOO_SMALL size probe, until the next apply.
 * Read reports EMPTY after a rejected command. Calls are synchronous and
 * serialized per ledger. Destroy only after draining calls.
 */
CREST_API crest_status_t CREST_CALL crest_permissions_create(uint64_t* out_handle);
CREST_API crest_status_t CREST_CALL crest_permissions_apply(
    uint64_t handle, const uint8_t* input_utf8, size_t input_length, size_t* out_length);
CREST_API crest_status_t CREST_CALL crest_permissions_read(
    uint64_t handle, uint8_t* destination, size_t capacity, size_t* out_length);
CREST_API crest_status_t CREST_CALL crest_permissions_destroy(uint64_t handle);

/* Bounded pure domain evaluation for incremental migration of synchronous
 * native APIs. No core handle, retained state, I/O, callbacks, or executor wait.
 * Input <= 16 KiB, output <= 64 KiB. Capacity 0 reports required size without
 * mutation; repeating the same request is deterministic. Caller owns buffers.
 */
CREST_API crest_status_t CREST_CALL crest_core_evaluate_policy(
    const uint8_t* input_utf8, size_t input_length,
    uint8_t* destination, size_t capacity, size_t* out_length);

/* Pure sync-record evaluation. Preserves the engine-independent wire format.
 * Buffers <= 16 MiB. No cloud I/O, callbacks, retained state or native objects.
 * Capacity probing does not mutate records or advance logical clocks. */
CREST_API crest_status_t CREST_CALL crest_core_evaluate_sync(
    const uint8_t* input_utf8, size_t input_length,
    uint8_t* destination, size_t capacity, size_t* out_length);

/* Immutable sync journal snapshots. Apply creates a new handle without changing
 * the input. Decode and persist the new snapshot before publishing it. All four
 * calls are worker-safe; each handle must be released. JSON inputs/outputs are
 * bounded to 64 MiB. INVALID_STATE from apply means logical clock exhaustion.
 * Read supports the usual BUFFER_TOO_SMALL size probe and does not consume.
 */
CREST_API crest_status_t CREST_CALL crest_sync_journal_create(
    const uint8_t* input, size_t input_length, uint64_t* out_handle);
CREST_API crest_status_t CREST_CALL crest_sync_journal_apply(
    uint64_t handle, const uint8_t* input, size_t input_length, uint64_t* out_handle);
/* On semantic failure, checked apply returns INVALID_MESSAGE and an optional
 * query-result handle containing the error. Read/release it with sync_query_*. */
CREST_API crest_status_t CREST_CALL crest_sync_journal_apply_checked(
    uint64_t handle, const uint8_t* input, size_t input_length,
    uint64_t* out_handle, uint64_t* out_error_query);
CREST_API crest_status_t CREST_CALL crest_sync_journal_read(
    uint64_t handle, uint8_t* destination, size_t capacity, size_t* out_length);
CREST_API crest_status_t CREST_CALL crest_sync_journal_release(uint64_t handle);

/* Prepared sync queries evaluate once and retain immutable JSON results.
 * Worker-safe, 64 MiB input/output limit; each handle must be released.
 * Read supports a non-consuming capacity probe. Semantic document errors are
 * encoded in the result envelope; malformed requests return a status error. */
CREST_API crest_status_t CREST_CALL crest_sync_query_prepare(
    const uint8_t* input, size_t input_length, uint64_t* out_handle);
CREST_API crest_status_t CREST_CALL crest_sync_query_read(
    uint64_t handle, uint8_t* destination, size_t capacity, size_t* out_length);
CREST_API crest_status_t CREST_CALL crest_sync_query_release(uint64_t handle);

// A session's sync component owns journal publication and stages the session's
// accepted edits itself, reporting SyncJournalChanged to the attached app.
// Prepare starts a transaction for the transport once any transaction in
// progress finishes; an overwrite supersedes the stages still queued. A merge
// or replacement changes the session with its journal, so it is an intent
// (crest_app_dispatch) and prepare refuses it. On a semantic failure only
// query may be returned, containing a typed error envelope. Commit publishes
// the journal; when its session keeps a file, commit first saves the journal
// with the newest accepted session and answers STORAGE_FAILED, leaving the
// transaction pending, when that fails. A journal a session commit already
// published is left alone.
CREST_API crest_status_t CREST_CALL crest_sync_authority_create(uint64_t journal, uint64_t *authority);
CREST_API crest_status_t CREST_CALL crest_sync_authority_release(uint64_t authority);
/* The journal the authority accepted last, as a new snapshot handle the caller
 * releases with crest_sync_journal_release. */
CREST_API crest_status_t CREST_CALL crest_sync_authority_snapshot(uint64_t authority, uint64_t *journal);
/* Counts the journals the authority accepted; a reader holding a snapshot reads
 * again when it changes. */
CREST_API crest_status_t CREST_CALL crest_sync_authority_version(uint64_t authority, uint64_t *version);
/* Blocks until every stage requested before the call has committed or failed,
 * without waiting out a coalescing delay. Call it off the UI thread. */
CREST_API crest_status_t CREST_CALL crest_sync_authority_flush(uint64_t authority);
CREST_API crest_status_t CREST_CALL crest_sync_authority_prepare(uint64_t authority,
    const uint8_t *input, size_t length, uint64_t *transaction, uint64_t *journal, uint64_t *query);
CREST_API crest_status_t CREST_CALL crest_sync_transaction_seal(uint64_t transaction, int32_t *accepted);
/* Commits a sealed transaction and writes the authority's version of its
 * journal, the one crest_sync_authority_version reported once it was accepted. */
CREST_API crest_status_t CREST_CALL crest_sync_transaction_commit(uint64_t transaction, uint64_t *version);
CREST_API crest_status_t CREST_CALL crest_sync_transaction_release(uint64_t transaction);

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif /* CREST_CORE_H */

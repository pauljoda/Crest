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
#define CREST_PROTOCOL_VERSION 1u

typedef uint64_t crest_core_handle_t;
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

typedef struct crest_core_options_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    const uint8_t* configuration_utf8;
    size_t configuration_length;
} crest_core_options_v1;

/* Returns the ABI major supported by this image. No core is required. */
CREST_API uint32_t CREST_CALL crest_core_abi_version(void);

/* Bounded pure domain evaluation for incremental migration of synchronous
 * native APIs. No core handle, retained state, I/O, callbacks, or executor wait.
 * Input <= 16 KiB, output <= 64 KiB. Capacity 0 reports required size without
 * mutation; repeating the same request is deterministic. Caller owns buffers.
 */
CREST_API crest_status_t CREST_CALL crest_core_evaluate_policy(
    const uint8_t* input_utf8, size_t input_length,
    uint8_t* destination, size_t capacity, size_t* out_length);

/* Synchronous domain edit of a single compact Space. No native effects, queues
 * or callbacks. Both buffers <= 4 MiB. Capacity probing is side-effect free;
 * caller supplies IDs and time so retrying produces the same result. */
CREST_API crest_status_t CREST_CALL crest_core_edit_session(
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
/* Prepares a matched session and journal after staging, merging, repair and
 * retention. On success both handles are owned by the caller. On semantic
 * failure only out_query may be returned, containing a typed error envelope.
 * The source journal and session authority are never mutated by preparation. */
CREST_API crest_status_t CREST_CALL crest_sync_session_prepare(
    uint64_t journal, const uint8_t* input, size_t input_length,
    uint64_t* out_journal, uint64_t* out_query);

/* Prepared sync queries evaluate once and retain immutable JSON results.
 * Worker-safe, 64 MiB input/output limit; each handle must be released.
 * Read supports a non-consuming capacity probe. Semantic document errors are
 * encoded in the result envelope; malformed requests return a status error. */
CREST_API crest_status_t CREST_CALL crest_sync_query_prepare(
    const uint8_t* input, size_t input_length, uint64_t* out_handle);
CREST_API crest_status_t CREST_CALL crest_sync_query_read(
    uint64_t handle, uint8_t* destination, size_t capacity, size_t* out_length);
CREST_API crest_status_t CREST_CALL crest_sync_query_release(uint64_t handle);

/* Native-UI session authority. All calls are exception-contained. Inputs and
 * checkpoint parts are <= 64 MiB; no native objects, disk I/O or callbacks.
 * Commits require the last accepted revision. Pair commits publish both or
 * neither, including when the second proposal is invalid. A checkpoint pins an
 * immutable revision; worker threads can read it while editing continues.
 * Native projections exclude favicon bytes, which remain platform assets.
 * Destroy/release only after the caller has drained its own references/calls.
 */
CREST_API crest_status_t CREST_CALL crest_session_create(
    const uint8_t* session, size_t length, uint64_t* out_session, uint64_t* out_revision);
CREST_API crest_status_t CREST_CALL crest_session_commit(
    uint64_t session, uint64_t expected_revision, const uint8_t* delta, size_t length, uint64_t* out_revision);
CREST_API crest_status_t CREST_CALL crest_session_commit_pair(
    uint64_t source, uint64_t source_revision, const uint8_t* source_delta, size_t source_length,
    uint64_t destination, uint64_t destination_revision, const uint8_t* destination_delta, size_t destination_length,
    uint64_t* out_source_revision, uint64_t* out_destination_revision);
CREST_API crest_status_t CREST_CALL crest_session_checkpoint(
    uint64_t session, uint64_t revision, const uint8_t* selection, size_t length, uint64_t* out_checkpoint);
/* part is "core" or a Space UUID for its history. Capacity probing never
 * consumes the immutable part. Part names are <= 64 UTF-8 bytes. */
CREST_API crest_status_t CREST_CALL crest_session_read_checkpoint(
    uint64_t checkpoint, const uint8_t* part, size_t part_length,
    uint8_t* destination, size_t capacity, size_t* out_length);
CREST_API crest_status_t CREST_CALL crest_session_destroy(uint64_t session);
CREST_API crest_status_t CREST_CALL crest_session_release_checkpoint(uint64_t checkpoint);

/* Commands operate on the owned session using only arguments and window
 * selection. Prepare/read do not mutate; decode the projection before commit.
 * Commit rejects a stale revision and a second commit of the same command.
 * Input/output <= 4 MiB. Always release the command, including failed commits.
 * Keep its originating session alive until the command is released. */
CREST_API crest_status_t CREST_CALL crest_session_prepare_command(
    uint64_t session, uint64_t expected_revision, const uint8_t* input, size_t length, uint64_t* out_command);
CREST_API crest_status_t CREST_CALL crest_session_read_command(
    uint64_t command, uint8_t* destination, size_t capacity, size_t* out_length);
CREST_API crest_status_t CREST_CALL crest_session_commit_command(uint64_t command, uint64_t* out_revision);
CREST_API crest_status_t CREST_CALL crest_session_release_command(uint64_t command);

/* Copies retained configuration; sets *out_core to 0 on failure.
 * Caller initializes struct_size to sizeof(crest_core_options_v1).
 * options and out_core must be non-null. Does not start the executor.
 */
CREST_API crest_status_t CREST_CALL crest_core_create(
    const crest_core_options_v1* options,
    crest_core_handle_t* out_core);

/* Configuring only. Copies a validated provider descriptor.
 * Registration is for trusted shipped code; it loads no native/managed code.
 */
CREST_API crest_status_t CREST_CALL crest_core_register_adapter(
    crest_core_handle_t core,
    const uint8_t* descriptor_utf8,
    size_t descriptor_length);

/* Validates required providers; starts the serialized semantic executor.
 * Returns transport/startup status, not a promise that native pages exist.
 */
CREST_API crest_status_t CREST_CALL crest_core_start(
    crest_core_handle_t core);

/* Thread-safe enqueue. Input is borrowed only until this call returns.
 * OK means copied and accepted; BUSY means not accepted and safe to retry.
 * Semantic completion/failure is reported through the outbox.
 */
CREST_API crest_status_t CREST_CALL crest_core_post(
    crest_core_handle_t core,
    const uint8_t* message_utf8,
    size_t message_length);

/* Dedicated transport worker only. Blocks on a notification, not a spin loop.
 * OK: output available. TIMEOUT: no change. STOPPED: outbox empty and no more
 * output can be produced. timeout_ms == 0 performs a nonblocking check.
 */
CREST_API crest_status_t CREST_CALL crest_core_wait_output(
    crest_core_handle_t core,
    uint32_t timeout_ms);

/* Single-consumer copy from outbox. out_length must be non-null.
 * With capacity 0, destination may be null. BUFFER_TOO_SMALL reports the
 * needed byte count and does not consume. OK copies/consumes one message.
 * EMPTY/STOPPED sets *out_length to 0. No trailing NUL is written.
 */
CREST_API crest_status_t CREST_CALL crest_core_read_output(
    crest_core_handle_t core,
    uint8_t* destination,
    size_t capacity,
    size_t* out_length);

/* Nonblocking, idempotent, irreversible shutdown request. Caller completes
 * cancelable native quit preflight first. Allows required terminal adapter
 * completions while quiescing. Wakes output waits as state/output changes.
 * Runtime shutdown may depend on host completion of final emitted effects.
 */
CREST_API crest_status_t CREST_CALL crest_core_begin_shutdown(
    crest_core_handle_t core);

/* Worker-only wait for stopped executor. Continue draining/routing final
 * output on the transport worker; do not deadlock it with this wait.
 * OK means stopped, TIMEOUT means still stopping. Does not consume output.
 */
CREST_API crest_status_t CREST_CALL crest_core_wait_stopped(
    crest_core_handle_t core,
    uint32_t timeout_ms);

/* Stopped/failed-before-start only; no concurrent calls, worker waits or
 * outstanding references may remain. Outbox must be drained. Invalidates
 * the numeric handle. Does not dlclose/FreeLibrary the containing image.
 */
CREST_API crest_status_t CREST_CALL crest_core_destroy(
    crest_core_handle_t core);

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif /* CREST_CORE_H */

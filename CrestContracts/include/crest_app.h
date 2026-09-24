#ifndef CREST_APP_H
#define CREST_APP_H

/* The typed application API. Intents, changes, rejections, queries and their
 * answers cross as the generated positional wire format; crest_contracts.h
 * names the tags and the schema fingerprint. Swift and the core always ship
 * in one build, so the wire has no versioning: creation checks the
 * fingerprint instead. Calls are synchronous and serialized per app.
 *
 * Every buffer the core returns was allocated by the core; release it with
 * crest_buffer_free. Statuses other than OK and REJECTED are caller or build
 * bugs: INVALID_MESSAGE (bytes that do not decode, or trailing bytes),
 * INVALID_HANDLE, VERSION_MISMATCH and INTERNAL_ERROR.
 */
#include "crest_core.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t* bytes;
    size_t length;
} crest_buffer_t;

/* A rule refused the intent or query; the buffer holds one rejection. */
#define CREST_REJECTED ((crest_status_t)6)

/* configuration is one encoded AppConfiguration. With a storage directory the
 * core opens session.sqlite there (creating both when absent), loads the
 * session it holds and saves every accepted revision to it; without one it
 * keeps everything in memory. VERSION_MISMATCH when the fingerprint is not
 * this core's schema. REJECTED: out_rejection holds one rejection naming why
 * the file cannot be used (StorageUnreadable, StorageFromNewerApp,
 * StorageRestoreInterrupted); nothing was written to it. */
CREST_API crest_status_t CREST_CALL crest_app_create(const uint8_t* fingerprint, size_t length,
    const uint8_t* configuration, size_t configuration_length, uint64_t* out_app, crest_buffer_t* out_rejection);
/* Saves any accepted revision still pending, then closes the session file.
 * Clear the wake callback first. */
CREST_API crest_status_t CREST_CALL crest_app_destroy(uint64_t app);
/* OK: buffer = published changes (a count, then each change). REJECTED: buffer = one rejection. */
CREST_API crest_status_t CREST_CALL crest_app_dispatch(uint64_t app, const uint8_t* intent, size_t length, crest_buffer_t* out);
/* OK: buffer = the answer. REJECTED: buffer = one rejection. */
CREST_API crest_status_t CREST_CALL crest_app_query(uint64_t app, const uint8_t* query, size_t length, crest_buffer_t* out);
CREST_API void CREST_CALL crest_buffer_free(crest_buffer_t* buffer);

/* Changes the core starts itself, such as Saved and StorageFailed, wait in a
 * pending batch. The wake callback carries nothing: it runs on whichever core
 * thread published the change, never while the core holds a lock, and only
 * when the batch goes from empty to not empty. Answer it by draining, on the
 * host's own thread. NULL removes the callback; when set_wake returns, no
 * earlier callback is still running. */
typedef void (CREST_CALL *crest_wake_t)(void* context);
CREST_API crest_status_t CREST_CALL crest_app_set_wake(uint64_t app, crest_wake_t callback, void* context);
/* OK: buffer = the pending changes, oldest first (a count, then each change). */
CREST_API crest_status_t CREST_CALL crest_app_drain(uint64_t app, crest_buffer_t* out);

/* TRANSITIONAL, removed when session intents land: the persistent session the
 * app keeps in storage, for the JSON session commands. EMPTY when the app has
 * no storage or its file holds no session yet. On OK the caller owns a session
 * handle (crest_session_destroy), its sync authority (crest_sync_authority_release)
 * and a projection command (crest_session_read_command, then
 * crest_session_release_command) that answers {"session", "assets",
 * "legacySelection"}: the session as loaded and repaired, which tab each
 * repaired tab's native images came from, and the selection an older release
 * stored in the session, when it stored one. */
CREST_API crest_status_t CREST_CALL crest_app_session(uint64_t app,
    uint64_t* out_session, uint64_t* out_revision, uint64_t* out_sync, uint64_t* out_projection);
/* TRANSITIONAL, removed when the core migrates the legacy session itself (3b):
 * writes the first session (stored-format JSON with each Space's history) and,
 * when journal_length is not zero, its sync journal in one transaction, then
 * loads it as a launch would. INVALID_STATE when the app has no storage or the
 * file already holds a session; STORAGE_FAILED when the write fails. */
CREST_API crest_status_t CREST_CALL crest_app_install_session(uint64_t app,
    const uint8_t* session, size_t session_length, const uint8_t* journal, size_t journal_length);

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif /* CREST_APP_H */

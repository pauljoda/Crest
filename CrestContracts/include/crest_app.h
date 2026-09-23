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

/* VERSION_MISMATCH when the fingerprint is not this core's schema. */
CREST_API crest_status_t CREST_CALL crest_app_create(const uint8_t* fingerprint, size_t length, uint64_t* out_app);
CREST_API crest_status_t CREST_CALL crest_app_destroy(uint64_t app);
/* OK: buffer = published changes (a count, then each change). REJECTED: buffer = one rejection. */
CREST_API crest_status_t CREST_CALL crest_app_dispatch(uint64_t app, const uint8_t* intent, size_t length, crest_buffer_t* out);
/* OK: buffer = the answer. REJECTED: buffer = one rejection. */
CREST_API crest_status_t CREST_CALL crest_app_query(uint64_t app, const uint8_t* query, size_t length, crest_buffer_t* out);
CREST_API void CREST_CALL crest_buffer_free(crest_buffer_t* buffer);

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif /* CREST_APP_H */

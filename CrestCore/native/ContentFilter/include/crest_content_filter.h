#ifndef CREST_CONTENT_FILTER_H
#define CREST_CONTENT_FILTER_H

/* Crest's content filter: Brave's adblock engine (adblock-rust) compiled into
 * the native core. The core owns which lists are compiled and which filter is
 * in force; an engine that checks requests itself is handed a slot and checks
 * against whatever the core installed there, from any thread.
 *
 * Every function returns a status unless it says otherwise, and catches the
 * library's own failures: a list the engine cannot digest fails one call.
 * Texts are UTF-8 and borrowed for the call. Buffers the library returns are
 * released with crest_content_filter_buffer_free.
 */
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Bumped with every change to this header's functions or records. */
#define CREST_CONTENT_FILTER_ABI_VERSION 3u

#define CREST_CONTENT_FILTER_OK ((int32_t)0)
#define CREST_CONTENT_FILTER_INVALID_ARGUMENT ((int32_t)1)
/* Saved data another version of the library wrote, or damaged data. */
#define CREST_CONTENT_FILTER_UNREADABLE ((int32_t)2)
#define CREST_CONTENT_FILTER_FAILED ((int32_t)3)

/* What a request asks for. */
enum {
    CREST_CONTENT_FILTER_OTHER = 0,
    CREST_CONTENT_FILTER_DOCUMENT = 1,
    CREST_CONTENT_FILTER_SUBDOCUMENT = 2,
    CREST_CONTENT_FILTER_SCRIPT = 3,
    CREST_CONTENT_FILTER_STYLESHEET = 4,
    CREST_CONTENT_FILTER_IMAGE = 5,
    CREST_CONTENT_FILTER_FONT = 6,
    CREST_CONTENT_FILTER_MEDIA = 7,
    CREST_CONTENT_FILTER_XMLHTTPREQUEST = 8,
    CREST_CONTENT_FILTER_WEBSOCKET = 9,
    CREST_CONTENT_FILTER_PING = 10,
    CREST_CONTENT_FILTER_OBJECT = 11,
    CREST_CONTENT_FILTER_CSP_REPORT = 12,
};

/* The request's HTTP method; UNKNOWN matches no $method filter. */
enum {
    CREST_CONTENT_FILTER_METHOD_UNKNOWN = 0,
    CREST_CONTENT_FILTER_GET = 1,
    CREST_CONTENT_FILTER_HEAD = 2,
    CREST_CONTENT_FILTER_POST = 3,
    CREST_CONTENT_FILTER_PUT = 4,
    CREST_CONTENT_FILTER_DELETE = 5,
    CREST_CONTENT_FILTER_CONNECT = 6,
    CREST_CONTENT_FILTER_OPTIONS = 7,
    CREST_CONTENT_FILTER_PATCH = 8,
    CREST_CONTENT_FILTER_METHOD_OTHER = 9,
};

/* A decision's verdict. */
#define CREST_CONTENT_FILTER_ALLOW ((uint8_t)0)
#define CREST_CONTENT_FILTER_BLOCK ((uint8_t)1)
/* Blocked, with a replacement resource to serve in its place. */
#define CREST_CONTENT_FILTER_REDIRECT ((uint8_t)2)

typedef struct crest_content_filter crest_content_filter_t;
typedef struct crest_content_filter_slot crest_content_filter_slot_t;

typedef struct {
    const uint8_t* bytes;
    size_t length;
} crest_content_filter_text_t;

typedef struct {
    uint8_t* bytes;
    size_t length;
} crest_content_filter_buffer_t;

typedef struct {
    crest_content_filter_text_t url;
    /* The document that makes the request: its frame's URL, or the URL itself
     * for a top-level navigation. */
    crest_content_filter_text_t source_url;
    uint8_t kind;
    uint8_t method;
} crest_content_filter_request_t;

typedef struct {
    uint8_t verdict;
} crest_content_filter_decision_t;

/* Not a status: CREST_CONTENT_FILTER_ABI_VERSION of the linked library. */
uint32_t crest_content_filter_abi_version(void);

/* Compiles count filter lists into one filter, retained once for the caller.
 * A filter that blocks only to serve a replacement resource ($redirect=) is
 * left out: no resources are loaded, so the request is allowed. */
int32_t crest_content_filter_build(const crest_content_filter_text_t* lists, size_t count,
    const crest_content_filter_t** out_filter);
/* Loads what crest_content_filter_save wrote with this same library, retained
 * once for the caller. The checksum is checked, but same-version data is
 * otherwise trusted: pass only data the core itself saved. */
int32_t crest_content_filter_load(const uint8_t* bytes, size_t length, const crest_content_filter_t** out_filter);
/* crest_content_filter_build and crest_content_filter_load with the resources
 * scriptlets and redirects use, as a JSON array in adblock-rust's resource
 * format; an empty text loads none. With resources, a filter that blocks to
 * serve a replacement stays in. A saved filter does not keep its resources.
 * Only the first `trusted` lists, which Crest itself chooses, may run the
 * scriptlets that need permission; a saved filter keeps that. */
int32_t crest_content_filter_build_with_resources(const crest_content_filter_text_t* lists, size_t count,
    size_t trusted, crest_content_filter_text_t resources, const crest_content_filter_t** out_filter);
int32_t crest_content_filter_load_with_resources(const uint8_t* bytes, size_t length,
    crest_content_filter_text_t resources, const crest_content_filter_t** out_filter);
int32_t crest_content_filter_save(const crest_content_filter_t* filter, crest_content_filter_buffer_t* out);
/* Not a status: lets go of one retention; the last frees the filter. */
void crest_content_filter_release(const crest_content_filter_t* filter);

int32_t crest_content_filter_check(const crest_content_filter_t* filter, const crest_content_filter_request_t* request,
    crest_content_filter_decision_t* out);
/* What a page at url hides and runs, as JSON: hide_selectors,
 * procedural_actions, exceptions, injected_script and generichide. */
int32_t crest_content_filter_page_resources(const crest_content_filter_t* filter, crest_content_filter_text_t url,
    crest_content_filter_buffer_t* out);
/* The generic hide selectors for the classes and ids a page shows, as a JSON
 * array. query is JSON with "classes", "ids" and "exceptions" arrays, the
 * exceptions being those the page's resources named. */
int32_t crest_content_filter_hidden_selectors(const crest_content_filter_t* filter, crest_content_filter_text_t query,
    crest_content_filter_buffer_t* out);

/* count filter lists as WebKit content rules, as JSON: "rules", the rules
 * that block or hide, and "exceptions", the ignore-previous-rules entries
 * that must follow the rules in every compiled list they are split into. */
int32_t crest_content_filter_content_rules(const crest_content_filter_text_t* lists, size_t count,
    crest_content_filter_buffer_t* out);

/* Not a status: frees and empties a buffer the library returned. */
void crest_content_filter_buffer_free(crest_content_filter_buffer_t* buffer);

/* Not a status: a slot holding no filter, which allows every request. */
crest_content_filter_slot_t* crest_content_filter_slot_create(void);
/* Puts filter in force, retaining it, or empties the slot for NULL. Checks
 * already under way finish with the filter they began with. */
int32_t crest_content_filter_slot_install(const crest_content_filter_slot_t* slot, const crest_content_filter_t* filter);
int32_t crest_content_filter_slot_check(const crest_content_filter_slot_t* slot,
    const crest_content_filter_request_t* request, crest_content_filter_decision_t* out);
/* crest_content_filter_slot_check that also answers the resource to serve in
 * place of a request the filter redirects: out says REDIRECT and redirect
 * receives the resource as a data URL, released with
 * crest_content_filter_buffer_free; otherwise redirect is left empty. */
int32_t crest_content_filter_slot_check_redirect(const crest_content_filter_slot_t* slot,
    const crest_content_filter_request_t* request, crest_content_filter_decision_t* out,
    crest_content_filter_buffer_t* redirect);
int32_t crest_content_filter_slot_page_resources(const crest_content_filter_slot_t* slot,
    crest_content_filter_text_t url, crest_content_filter_buffer_t* out);
/* Not a status: destroys the slot and lets go of its filter. */
void crest_content_filter_slot_destroy(crest_content_filter_slot_t* slot);

#ifdef __cplusplus
}
#endif

#endif /* CREST_CONTENT_FILTER_H */

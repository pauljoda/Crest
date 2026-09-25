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

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif /* CREST_CORE_H */

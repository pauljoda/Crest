#include "crest_core.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void access_boundary(void) {
    uint64_t access = 0, request = 0;
    uint8_t space[16] = {1}, profile[16] = {2}, replacement[16] = {3};
    int32_t locked = 0, applied = 0;
    assert(crest_access_create(&access) == CREST_OK && access != 0);
    assert(crest_access_is_locked(access, NULL, profile, 1, &locked) == CREST_INVALID_ARGUMENT && locked == 1);
    assert(crest_access_is_locked(access, space, profile, 2, &locked) == CREST_INVALID_ARGUMENT && locked == 1);
    assert(crest_access_begin(access, space, profile, 1, &request) == CREST_OK && request != 0);
    assert(crest_access_complete(access, space, replacement, request, 1) == CREST_INVALID_STATE);
    assert(crest_access_lock_all(access, 1, &applied) == CREST_OK && applied == 0);
    assert(crest_access_complete(access, space, profile, request, 1) == CREST_OK);
    assert(crest_access_is_locked(access, space, profile, 1, &locked) == CREST_OK && locked == 0);
    assert(crest_access_lock_space(access, space) == CREST_OK);
    assert(crest_access_complete(access, space, profile, request, 1) == CREST_INVALID_STATE);
    assert(crest_access_is_locked(access, space, profile, 1, &locked) == CREST_OK && locked == 1);
    assert(crest_access_destroy(access) == CREST_OK);
    assert(crest_access_is_locked(access, space, profile, 1, &locked) == CREST_INVALID_HANDLE && locked == 1);
}
static void policy_boundary(void) {
    const char *request = "{\"version\":1,\"operation\":\"address.intent\",\"input\":\"localhost:8767/profile\",\"searchTemplate\":\"https://duckduckgo.com/?q=%s\"}";
    size_t length = 0;
    assert(crest_core_evaluate_policy(NULL, 0, NULL, 0, &length) == CREST_INVALID_ARGUMENT);
    assert(crest_core_evaluate_policy((const uint8_t*)request, strlen(request), NULL, 0, &length) == CREST_BUFFER_TOO_SMALL);
    assert(length > 0 && length < 256);
    uint8_t output[257]; memset(output, 0xa5, sizeof(output));
    size_t required = length;
    assert(crest_core_evaluate_policy((const uint8_t*)request, strlen(request), output, length - 1, &length) == CREST_BUFFER_TOO_SMALL);
    assert(length == required && output[0] == 0xa5);
    assert(crest_core_evaluate_policy((const uint8_t*)request, strlen(request), output, 256, &length) == CREST_OK);
    assert(output[length] == 0xa5); output[length] = 0;
    assert(strstr((const char*)output, "http://localhost:8767/profile"));
    const uint8_t invalid[] = { 0xff };
    assert(crest_core_evaluate_policy(invalid, sizeof(invalid), output, 256, &length) == CREST_INVALID_MESSAGE);
    assert(length == 0);
}
static const char* space_id = "44444444-4444-4444-4444-444444444444";
static const char* profile_id = "55555555-5555-5555-5555-555555555555";
static void session_boundary(void) {
    char json[1024];
    int size = snprintf(json, sizeof(json),
        "{\"selectedSpaceID\":{\"rawValue\":\"%s\"},\"spaces\":[{\"id\":{\"rawValue\":\"%s\"},"
        "\"profile\":{\"id\":\"%s\"},\"name\":\"Reading\",\"tabs\":[],\"folders\":[],"
        "\"history\":[],\"archivedTabs\":[]}]}", space_id, space_id, profile_id);
    assert(size > 0 && (size_t)size < sizeof(json));
    uint64_t session = 999, revision = 999;
    assert(crest_session_create(NULL, 0, &session, &revision) == CREST_INVALID_ARGUMENT
        && session == 0 && revision == 0);
    assert(crest_session_create((const uint8_t*)"{}", 2, &session, &revision) == CREST_INVALID_MESSAGE
        && session == 0);
    assert(crest_session_create((const uint8_t*)json, (size_t)size, &session, &revision) == CREST_OK
        && session != 0 && revision == 1);
    memset(json, 0xaa, sizeof(json)); /* The core must own its session copy. */

    /* The remaining v1 descriptor contract: process-local engine registration. */
    const char* capability = "{\"status\":\"supported\",\"contractVersion\":1,\"scope\":\"native ABI test\",\"limitations\":[],\"evidence\":\"native consumer\"}";
    char engine[2048];
    size = snprintf(engine, sizeof(engine),
        "{\"adapterId\":\"engine\",\"role\":\"engine\",\"implementationId\":\"fixture\","
        "\"implementationVersion\":\"1\",\"protocolVersion\":%u,\"capabilities\":{\"pages\":%s,\"navigation\":%s}}",
        CREST_PROTOCOL_VERSION, capability, capability);
    assert(size > 0 && (size_t)size < sizeof(engine));
    assert(crest_session_register_engine(session + 1000, (const uint8_t*)engine, (size_t)size) == CREST_INVALID_HANDLE);
    assert(crest_session_register_engine(session, (const uint8_t*)engine, (size_t)size) == CREST_OK);
    assert(crest_session_register_engine(session, (const uint8_t*)engine, (size_t)size) == CREST_INVALID_MESSAGE);
    memset(engine, 0xaa, sizeof(engine)); /* The session must own its descriptor copy. */

    char selection[512];
    size = snprintf(selection, sizeof(selection),
        "{\"selectedSpaceID\":{\"rawValue\":\"%s\"},\"selectedTabs\":[{\"spaceID\":{\"rawValue\":\"%s\"},\"tabID\":null}]}",
        space_id, space_id);
    assert(size > 0 && (size_t)size < sizeof(selection));
    uint64_t checkpoint = 0;
    assert(crest_session_checkpoint(session, revision + 1, (const uint8_t*)selection, (size_t)size, &checkpoint)
        == CREST_INVALID_STATE && checkpoint == 0);
    assert(crest_session_checkpoint(session, revision, (const uint8_t*)selection, (size_t)size, &checkpoint) == CREST_OK
        && checkpoint != 0);

    /* A capacity probe reports the size without consuming the immutable part. */
    const char* part = "core";
    size_t length = 0, again = 0;
    assert(crest_session_read_checkpoint(checkpoint, (const uint8_t*)part, strlen(part), NULL, 0, &length)
        == CREST_BUFFER_TOO_SMALL && length > 0);
    uint8_t* output = malloc(length + 1); assert(output); output[length] = 0xa5;
    assert(crest_session_read_checkpoint(checkpoint, (const uint8_t*)part, strlen(part), output, length - 1, &again)
        == CREST_BUFFER_TOO_SMALL && again == length);
    assert(crest_session_read_checkpoint(checkpoint, (const uint8_t*)part, strlen(part), output, length, &again) == CREST_OK
        && again == length && output[length] == 0xa5);
    output[length] = 0;
    /* Engine registration is process-local and never enters the checkpoint. */
    assert(strstr((const char*)output, "fixture") == NULL);
    free(output);

    assert(crest_session_release_checkpoint(checkpoint) == CREST_OK);
    assert(crest_session_release_checkpoint(checkpoint) == CREST_INVALID_HANDLE);
    assert(crest_session_destroy(session) == CREST_OK);
    assert(crest_session_destroy(session) == CREST_INVALID_HANDLE);
    assert(crest_session_checkpoint(session, 1, (const uint8_t*)selection, (size_t)size, &checkpoint) == CREST_INVALID_HANDLE);
}
/* A session that consults the access authority refuses commands against a
 * locked Space until that exact Space/profile pair holds a grant. */
static void locked_space_boundary(void) {
    static const char* tab_id = "66666666-6666-6666-6666-666666666666";
    char json[1024];
    int size = snprintf(json, sizeof(json),
        "{\"selectedSpaceID\":{\"rawValue\":\"%s\"},\"spaces\":[{\"id\":{\"rawValue\":\"%s\"},"
        "\"profile\":{\"id\":\"%s\"},\"name\":\"Reading\",\"accessPolicy\":\"deviceOwnerAuthentication\","
        "\"tabs\":[{\"id\":{\"rawValue\":\"%s\"},\"title\":\"Page\",\"url\":\"https://example.com/\","
        "\"placement\":\"current\",\"lastActivatedAt\":800000000}"
        "],\"selectedTabID\":{\"rawValue\":\"%s\"},\"folders\":[],\"history\":[],\"archivedTabs\":[]}]}",
        space_id, space_id, profile_id, tab_id, tab_id);
    assert(size > 0 && (size_t)size < sizeof(json));
    uint64_t session = 0, revision = 0, access = 0, command = 0, request = 0;
    assert(crest_session_create((const uint8_t*)json, (size_t)size, &session, &revision) == CREST_OK);
    assert(crest_access_create(&access) == CREST_OK);
    assert(crest_session_attach_access(session, access + 1000) == CREST_INVALID_HANDLE);
    assert(crest_session_attach_access(session, access) == CREST_OK);
    assert(crest_session_attach_access(session, access) == CREST_OK);

    char edit[1024];
    size = snprintf(edit, sizeof(edit),
        "{\"version\":1,\"operation\":\"tab.rename\",\"spaceId\":{\"rawValue\":\"%s\"},"
        "\"profileId\":\"%s\",\"now\":800000002,"
        "\"arguments\":{\"tabId\":\"%s\",\"title\":\"Renamed\"},"
        "\"window\":{\"selectedSpaceID\":{\"rawValue\":\"%s\"},"
        "\"selectedTabs\":[{\"spaceID\":{\"rawValue\":\"%s\"},\"tabID\":{\"rawValue\":\"%s\"}}]}}",
        space_id, profile_id, tab_id, space_id, space_id, tab_id);
    assert(size > 0 && (size_t)size < sizeof(edit));
    assert(crest_session_prepare_command(session, revision, (const uint8_t*)edit, (size_t)size, &command)
        == CREST_INVALID_MESSAGE && command == 0);

    uint8_t space[16], profile[16];
    memset(space, 0x44, sizeof(space)); memset(profile, 0x55, sizeof(profile));
    assert(crest_access_begin(access, space, profile, 1, &request) == CREST_OK && request != 0);
    assert(crest_access_complete(access, space, profile, request, 1) == CREST_OK);
    assert(crest_session_prepare_command(session, revision, (const uint8_t*)edit, (size_t)size, &command) == CREST_OK
        && command != 0);
    assert(crest_session_release_command(command) == CREST_OK);

    assert(crest_access_lock_space(access, space) == CREST_OK);
    command = 0;
    assert(crest_session_prepare_command(session, revision, (const uint8_t*)edit, (size_t)size, &command)
        == CREST_INVALID_MESSAGE && command == 0);
    assert(crest_access_destroy(access) == CREST_OK);
    assert(crest_session_destroy(session) == CREST_OK);
}
int main(void) {
    assert(crest_core_abi_version() == CREST_ABI_VERSION);
    policy_boundary();
    access_boundary();
    session_boundary();
    locked_space_boundary();
    puts("Native ABI buffer ownership, size retry, handle, session and lock checks passed.");
    return 0;
}

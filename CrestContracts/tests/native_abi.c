#include "crest_core.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char* session = "11111111-1111-1111-1111-111111111111";
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
static void descriptor(crest_core_handle_t core, const char* role) {
    char json[2048];
    const char* capability = "{\"status\":\"supported\",\"contractVersion\":1,\"scope\":\"native ABI test\",\"limitations\":[],\"evidence\":\"native consumer\"}";
    int length = snprintf(json, sizeof(json),
        "{\"adapterId\":\"%s\",\"role\":\"%s\",\"implementationId\":\"fixture\",\"implementationVersion\":\"1\",\"protocolVersion\":1,"
        "\"capabilities\":{\"pages\":%s,\"navigation\":%s,\"surfaces\":%s}}", role, role, capability, capability, capability);
    assert(length > 0 && (size_t)length < sizeof(json));
    assert(crest_core_register_adapter(core, (const uint8_t*)json, length) == CREST_OK);
    memset(json, 0xaa, sizeof(json)); /* The core must own its descriptor copy. */
}
static void extract_id(const char* json, const char* key, char out[37]) {
    char needle[64]; snprintf(needle, sizeof(needle), "\"%s\":\"", key);
    const char* value = strstr(json, needle); assert(value); value += strlen(needle);
    memcpy(out, value, 36); out[36] = 0; assert(value[36] == '"');
}
int main(void) {
    assert(crest_core_abi_version() == CREST_ABI_VERSION);
    policy_boundary();
    access_boundary();
    crest_core_handle_t core = 999;
    assert(crest_core_create(NULL, &core) == CREST_INVALID_ARGUMENT && core == 0);
    char config[512];
    int size = snprintf(config, sizeof(config), "{\"sessionId\":\"%s\",\"protocolVersion\":1,\"isolationMode\":\"ephemeral\",\"queueByteLimit\":8192,\"messageByteLimit\":4096}", session);
    crest_core_options_v1 options = { sizeof(options), 99, (const uint8_t*)config, (size_t)size };
    assert(crest_core_create(&options, &core) == CREST_VERSION_MISMATCH && core == 0);
    options.abi_version = CREST_ABI_VERSION;
    assert(crest_core_create(&options, &core) == CREST_OK && core != 0);
    memset(config, 0xaa, sizeof(config));
    assert(crest_core_start(core) == CREST_INVALID_STATE);
    descriptor(core, "ui"); descriptor(core, "engine"); descriptor(core, "platform");
    assert(crest_core_start(core) == CREST_OK);
    assert(crest_core_destroy(core) == CREST_INVALID_STATE);
    assert(crest_core_post(core, NULL, 10) == CREST_INVALID_ARGUMENT);
    char command[1024];
    size = snprintf(command, sizeof(command), "{\"protocolVersion\":1,\"sessionId\":\"%s\",\"id\":\"22222222-2222-2222-2222-222222222222\",\"correlationId\":\"22222222-2222-2222-2222-222222222222\",\"causationId\":null,\"sender\":\"ui\",\"recipient\":\"core\",\"sequence\":\"1\",\"kind\":\"command\",\"type\":\"core.snapshot\",\"payload\":{}}", session);
    assert(crest_core_post(core, (const uint8_t*)command, size) == CREST_OK);
    assert(crest_core_post(core, (const uint8_t*)command, size) == CREST_OK);
    memset(command, 0xaa, sizeof(command));
    assert(crest_core_wait_output(core, 2000) == CREST_OK);
    size_t length = 0, second_length = 0;
    assert(crest_core_read_output(core, NULL, 0, &length) == CREST_BUFFER_TOO_SMALL);
    assert(length > 0 && length <= 4096);
    uint8_t* output = malloc(4097); assert(output);
    assert(crest_core_read_output(core, output, length - 1, &second_length) == CREST_BUFFER_TOO_SMALL);
    assert(length == second_length);
    assert(crest_core_read_output(core, output, 4096, &length) == CREST_OK);
    output[length] = 0; assert(strstr((char*)output, "ui.snapshot"));
    assert(crest_core_begin_shutdown(core) == CREST_OK);
    assert(crest_core_begin_shutdown(core) == CREST_OK);
    assert(crest_core_wait_stopped(core, 0) == CREST_TIMEOUT);
    int count = 0;
    while (crest_core_wait_output(core, 2000) != CREST_STOPPED) {
        assert(++count < 20);
        assert(crest_core_read_output(core, output, 4096, &length) == CREST_OK);
        output[length] = 0;
        if (strstr((char*)output, "engine.dispose_all")) {
            char id[37], correlation[37];
            extract_id((char*)output, "id", id); extract_id((char*)output, "correlationId", correlation);
            size = snprintf(command, sizeof(command), "{\"protocolVersion\":1,\"sessionId\":\"%s\",\"id\":\"33333333-3333-3333-3333-333333333333\",\"correlationId\":\"%s\",\"causationId\":\"%s\",\"sender\":\"engine\",\"recipient\":\"core\",\"sequence\":\"1\",\"kind\":\"observation\",\"type\":\"engine.stopped\",\"payload\":{}}", session, correlation, id);
            assert(crest_core_post(core, (const uint8_t*)command, size) == CREST_OK);
        }
    }
    assert(crest_core_wait_stopped(core, 2000) == CREST_OK);
    assert(crest_core_destroy(core) == CREST_OK);
    assert(crest_core_start(core) == CREST_INVALID_HANDLE);
    free(output);
    puts("Native ABI ownership, size retry, identity, and shutdown checks passed.");
    return 0;
}

#define _POSIX_C_SOURCE 200809L
#include "crest_app.h"
#include "crest_contracts.h"
#include "crest_core.h"
#include "crest_engine.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

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
static void app_boundary(void) {
    const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
    uint8_t stale[CREST_CONTRACTS_FINGERPRINT_LENGTH];
    memcpy(stale, fingerprint, sizeof(stale)); stale[0] ^= 1;
    /* AppConfiguration(StorageDirectory: null): the optional string is absent. */
    const uint8_t memory_only[] = { 0 };
    uint64_t app = 0;
    crest_buffer_t buffer = { (uint8_t*)1, 1 };
    assert(crest_app_create(stale, sizeof(stale), memory_only, sizeof(memory_only), &app, &buffer) == CREST_VERSION_MISMATCH
        && app == 0 && buffer.bytes == NULL);
    assert(crest_app_create(fingerprint, sizeof(fingerprint), memory_only, sizeof(memory_only), &app, &buffer) == CREST_OK
        && app != 0 && buffer.bytes == NULL);
    /* A union tag no contract uses is malformed input, not a rejection. */
    const uint8_t garbage[] = { 0x7f, 0x01, 0x02 };
    assert(crest_app_dispatch(app, garbage, sizeof(garbage), &buffer) == CREST_INVALID_MESSAGE);
    assert(buffer.bytes == NULL && buffer.length == 0);
    /* AcknowledgeDownloads: its tag, then the profile's 16 RFC 4122 bytes. */
    uint8_t acknowledge[17] = { CREST_INTENT_ACKNOWLEDGE_DOWNLOADS };
    for (int index = 1; index < 17; index++) acknowledge[index] = (uint8_t)index;
    assert(crest_app_dispatch(app, acknowledge, sizeof(acknowledge), &buffer) == CREST_OK);
    /* Nothing to acknowledge: a change list with a count of zero. */
    assert(buffer.bytes != NULL && buffer.length == 1 && buffer.bytes[0] == 0);
    crest_buffer_free(&buffer);
    assert(buffer.bytes == NULL && buffer.length == 0);
    crest_buffer_free(&buffer);
    /* CredentialSave: the match, then the platform's comparison with it. No
     * password crosses; an unchanged one is already stored. */
    uint8_t save[36] = { CREST_QUERY_CREDENTIAL_SAVE, 1 };
    memset(save + 2, 0x55, 16);
    save[18] = 1;
    memset(save + 19, 0x55, 16);
    save[35] = 1;
    assert(crest_app_query(app, save, sizeof(save), &buffer) == CREST_OK);
    assert(buffer.length == 18 && buffer.bytes[0] == 2 && buffer.bytes[1] == 1 && buffer.bytes[17] == 0x55);
    crest_buffer_free(&buffer);
    /* A comparison with another record is stale: one rejection, no fields. */
    memset(save + 19, 0x66, 16);
    assert(crest_app_query(app, save, sizeof(save), &buffer) == CREST_REJECTED);
    assert(buffer.length == 1 && buffer.bytes[0] == CREST_REJECTION_STALE_CREDENTIAL_COMPARISON);
    crest_buffer_free(&buffer);
    assert(crest_app_destroy(app) == CREST_OK);
    assert(crest_app_dispatch(app, acknowledge, sizeof(acknowledge), &buffer) == CREST_INVALID_HANDLE);
    assert(crest_app_destroy(app) == CREST_INVALID_HANDLE);
}
static void permissions_boundary(void) {
    const char *set = "{\"version\":1,\"command\":\"set\",\"spaceID\":\"77777777-7777-7777-7777-777777777777\","
        "\"origin\":{\"scheme\":\"https\",\"host\":\"meet.example\",\"port\":443},\"permission\":\"camera\","
        "\"decision\":\"grantPersistently\",\"recordID\":\"88888888-8888-8888-8888-888888888888\",\"now\":1,\"locked\":false}";
    const char *locked = "{\"version\":1,\"command\":\"decision\",\"spaceID\":\"77777777-7777-7777-7777-777777777777\","
        "\"origin\":{\"scheme\":\"https\",\"host\":\"meet.example\",\"port\":443},\"permission\":\"camera\",\"locked\":true}";
    const char *unknown = "{\"version\":1,\"command\":\"grant_everything\"}";
    uint64_t ledger = 0;
    size_t length = 0, required = 0;
    uint8_t output[1024]; memset(output, 0xa5, sizeof(output));
    assert(crest_permissions_create(&ledger) == CREST_OK && ledger != 0);
    assert(crest_permissions_read(ledger, output, sizeof(output), &length) == CREST_EMPTY && length == 0);
    assert(crest_permissions_apply(ledger, (const uint8_t*)set, strlen(set), &required) == CREST_OK && required > 0);
    assert(crest_permissions_read(ledger, NULL, 0, &length) == CREST_BUFFER_TOO_SMALL && length == required);
    assert(crest_permissions_read(ledger, output, required - 1, &length) == CREST_BUFFER_TOO_SMALL && output[0] == 0xa5);
    assert(crest_permissions_read(ledger, output, sizeof(output) - 1, &length) == CREST_OK && length == required);
    assert(output[length] == 0xa5); output[length] = 0;
    assert(strstr((const char*)output, "\"applied\":true") && strstr((const char*)output, "88888888-8888-8888-8888-888888888888"));
    /* A locked Space answers Ask even with a saved grant. */
    assert(crest_permissions_apply(ledger, (const uint8_t*)locked, strlen(locked), &length) == CREST_OK);
    assert(crest_permissions_read(ledger, output, sizeof(output) - 1, &length) == CREST_OK);
    output[length] = 0;
    assert(strcmp((const char*)output, "{\"decision\":\"ask\"}") == 0);
    /* An unknown command is rejected and leaves nothing to read. */
    assert(crest_permissions_apply(ledger, (const uint8_t*)unknown, strlen(unknown), &length) == CREST_INVALID_MESSAGE && length == 0);
    assert(crest_permissions_read(ledger, output, sizeof(output), &length) == CREST_EMPTY);
    assert(crest_permissions_destroy(ledger) == CREST_OK);
    assert(crest_permissions_apply(ledger, (const uint8_t*)set, strlen(set), &length) == CREST_INVALID_HANDLE);
}
static void policy_boundary(void) {
    const char *request = "{\"version\":1,\"operation\":\"address.intent\",\"input\":\"localhost:8767/profile\",\"searchProvider\":{\"id\":\"duckDuckGo\"}}";
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
    /* Search URLs are built by the core catalog, identical for every engine. */
    const char *search = "{\"version\":1,\"operation\":\"search.url\",\"searchProvider\":{\"id\":\"google\"},"
        "\"query\":\"a+b & c#d\",\"purpose\":\"search\"}";
    assert(crest_core_evaluate_policy((const uint8_t*)search, strlen(search), output, 256, &length) == CREST_OK);
    output[length] = 0;
    assert(strstr((const char*)output, "https://www.google.com/search?q=a%2Bb%20%26%20c%23d"));
    const char *translation = "{\"version\":1,\"operation\":\"translation.rule\",\"sourceID\":\"zh-TW\","
        "\"rules\":{\"sources\":{\"zh-Hant\":{\"targetID\":\"en\",\"isEnabled\":true}}}}";
    assert(crest_core_evaluate_policy((const uint8_t*)translation, strlen(translation), output, 256, &length) == CREST_OK);
    output[length] = 0;
    assert(strstr((const char*)output, "\"target\":\"en\""));
    const uint8_t invalid[] = { 0xff };
    assert(crest_core_evaluate_policy(invalid, sizeof(invalid), output, 256, &length) == CREST_INVALID_MESSAGE);
    assert(length == 0);
    const char *setup = "{\"version\":1,\"operation\":\"setup.tab\",\"placement\":\"pinned\",\"existingPinnedCount\":12,"
        "\"addedPinnedCount\":0,\"url\":\"https://example.com/\",\"title\":null}";
    assert(crest_core_evaluate_policy((const uint8_t*)setup, strlen(setup), output, 256, &length) == CREST_OK);
    output[length] = 0;
    assert(strstr((const char*)output, "\"error\":\"pinned_limit_reached\""));
    /* Shortcut conflicts, launch isolation and media arbitration are core rules. */
    char answer[2048];
    const char *conflict = "{\"version\":1,\"operation\":\"shortcuts.assign\",\"platform\":\"desktop\","
        "\"commands\":[\"newTab\",\"findInPage\"],\"overrides\":{},\"command\":\"newTab\","
        "\"shortcut\":{\"key\":{\"character\":\"f\"},\"modifiers\":1},\"replacingConflicts\":false}";
    assert(crest_core_evaluate_policy((const uint8_t*)conflict, strlen(conflict), (uint8_t*)answer, sizeof(answer) - 1, &length) == CREST_OK);
    answer[length] = 0;
    assert(strstr(answer, "\"result\":\"conflict\"") && strstr(answer, "\"conflicts\":[\"findInPage\"]"));
    const char *launch = "{\"version\":1,\"operation\":\"launch.plan\",\"platform\":\"mobile\",\"environment\":{"
        "\"testRuntime\":false,\"previewRuntime\":false,\"isolatedSession\":false,\"namedProfile\":false,"
        "\"isolatedCloudSync\":false,\"resetSession\":true,\"showcase\":false,\"inMemoryCredentials\":false,"
        "\"onboardingWelcome\":false,\"desktopSetup\":false,\"mobileSetup\":false,\"performanceHarness\":false,"
        "\"updateTestFeed\":false},\"hasActiveLaunchGate\":false}";
    assert(crest_core_evaluate_policy((const uint8_t*)launch, strlen(launch), (uint8_t*)answer, sizeof(answer) - 1, &length) == CREST_OK);
    answer[length] = 0;
    assert(strstr(answer, "\"requiresIsolation\":true") && strstr(answer, "\"startupBehavior\":\"lastActiveTab\""));
    const char *media = "{\"version\":1,\"operation\":\"media.arbitrate\",\"sessions\":["
        "{\"id\":\"tab:b\",\"ordinal\":2,\"playbackState\":\"playing\",\"audible\":true},"
        "{\"id\":\"tab:a\",\"ordinal\":1,\"playbackState\":\"paused\",\"audible\":true}]}";
    assert(crest_core_evaluate_policy((const uint8_t*)media, strlen(media), (uint8_t*)answer, sizeof(answer) - 1, &length) == CREST_OK);
    answer[length] = 0;
    assert(strstr(answer, "\"order\":[1,0]") && strstr(answer, "\"nowPlaying\":0"));
    const char *metadata = "{\"version\":1,\"operation\":\"media.arbitrate\",\"sessions\":["
        "{\"id\":\"tab:a\",\"ordinal\":1,\"playbackState\":\"paused\",\"audible\":true,\"title\":\"Song\"}]}";
    assert(crest_core_evaluate_policy((const uint8_t*)metadata, strlen(metadata), (uint8_t*)answer, sizeof(answer) - 1, &length) == CREST_INVALID_MESSAGE);
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
    uint64_t session = 999;
    assert(crest_session_create(NULL, 0, &session) == CREST_INVALID_ARGUMENT && session == 0);
    assert(crest_session_create((const uint8_t*)"{}", 2, &session) == CREST_INVALID_MESSAGE && session == 0);
    assert(crest_session_create((const uint8_t*)json, (size_t)size, &session) == CREST_OK && session != 0);
    memset(json, 0xaa, sizeof(json)); /* The core must own its session copy. */

    assert(crest_session_destroy(session) == CREST_OK);
    assert(crest_session_destroy(session) == CREST_INVALID_HANDLE);
}
/* A binding under test: what attach handed it and the commands it ran. */
typedef struct {
    uint64_t app, engine;
    crest_engine_report_t report;
    int commands;
    uint8_t last[64];
    size_t last_length;
} engine_fixture_t;
static void CREST_CALL attach_engine(void* context, uint64_t app, uint64_t engine, crest_engine_report_t report) {
    engine_fixture_t* fixture = context;
    fixture->app = app; fixture->engine = engine; fixture->report = report;
}
static void CREST_CALL run_engine(void* context, const uint8_t* command, size_t length) {
    engine_fixture_t* fixture = context;
    assert(length <= sizeof(fixture->last));
    memcpy(fixture->last, command, length);
    fixture->last_length = length;
    fixture->commands++;
}
/* An engine binding registers through its function table, runs the command
 * that opening a page causes, and reports back; reports are never refused. */
static void engine_boundary(void) {
    const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
    const uint8_t engine_fingerprint[CREST_ENGINE_CONTRACT_FINGERPRINT_LENGTH] = CREST_ENGINE_CONTRACT_FINGERPRINT;
    const uint8_t memory_only[] = { 0 };
    uint64_t app = 0, engine = 0;
    crest_buffer_t buffer = { NULL, 0 };
    assert(crest_app_create(fingerprint, sizeof(fingerprint), memory_only, sizeof(memory_only), &app, &buffer) == CREST_OK);
    /* EngineRegistration: WebKit (its index in EngineKind.All), the required
     * capabilities as their indexes in EngineCapability.All (pages,
     * navigation, workspace-profiles, profile-deletion), then IsDefault. */
    const uint8_t registration[] = { 1, 4, 0, 1, 7, 9, 1 };
    engine_fixture_t fixture = { 0 };
    const crest_engine_binding_t binding = { &fixture, attach_engine, run_engine };
    assert(crest_engine_register(app, fingerprint, sizeof(fingerprint), registration, sizeof(registration), &binding,
        &engine, &buffer) == CREST_VERSION_MISMATCH && engine == 0 && fixture.engine == 0);
    assert(crest_engine_register(app, engine_fingerprint, sizeof(engine_fingerprint), registration, sizeof(registration),
        &binding, &engine, &buffer) == CREST_OK && engine != 0 && buffer.bytes == NULL);
    assert(fixture.app == app && fixture.engine == engine && fixture.report == crest_engine_report);
    assert(crest_engine_register(app, engine_fingerprint, sizeof(engine_fingerprint), registration, sizeof(registration),
        &binding, &engine, &buffer) == CREST_REJECTED && buffer.bytes[0] == CREST_REJECTION_ENGINE_ALREADY_REGISTERED);
    crest_buffer_free(&buffer);
    engine = fixture.engine;

    /* A session attached to the app's device, with a window open over it. */
    char json[1024];
    int size = snprintf(json, sizeof(json),
        "{\"spaces\":[{\"id\":{\"rawValue\":\"%s\"},\"profile\":{\"id\":\"%s\"},\"name\":\"Reading\",\"tabs\":[],"
        "\"folders\":[],\"history\":[],\"archivedTabs\":[]}]}", space_id, profile_id);
    assert(size > 0 && (size_t)size < sizeof(json));
    uint64_t session = 0;
    assert(crest_session_create((const uint8_t*)json, (size_t)size, &session) == CREST_OK);
    uint8_t workspace[16];
    assert(crest_session_attach_device(session, app, workspace) == CREST_OK);
    /* OpenWindow: the window, the workspace, not saved, nothing to copy or show,
     * RestoresTabs. It answers the pending WorkspaceOpened first, then its
     * own WindowChanged. */
    uint8_t opening[38] = { CREST_INTENT_OPEN_WINDOW };
    memset(opening + 1, 0x42, 16);
    memcpy(opening + 17, workspace, 16);
    opening[37] = 1;
    assert(crest_app_dispatch(app, opening, sizeof(opening), &buffer) == CREST_OK);
    assert(buffer.bytes[0] == 2 && buffer.bytes[1] == CREST_CHANGE_WORKSPACE_OPENED);
    crest_buffer_free(&buffer);

    /* OpenPage: the page, the workspace, the Space (all 0x44), no tab, the
     * window. The dispatch returns once the binding ran CreatePage: the page,
     * the Space's profile (all 0x55) and whether it is private. */
    uint8_t page[66] = { CREST_INTENT_OPEN_PAGE };
    memset(page + 1, 0x61, 16);
    memcpy(page + 17, workspace, 16);
    memset(page + 33, 0x44, 16);
    page[49] = 0;
    memset(page + 50, 0x42, 16);
    assert(crest_app_dispatch(app, page, sizeof(page), &buffer) == CREST_OK);
    assert(buffer.bytes[0] == 1 && buffer.bytes[1] == CREST_CHANGE_PAGE_OPENED);
    crest_buffer_free(&buffer);
    assert(fixture.commands == 1 && fixture.last_length == 34 && fixture.last[0] == CREST_ENGINE_COMMAND_CREATE_PAGE);
    assert(memcmp(fixture.last + 1, page + 1, 16) == 0 && fixture.last[17] == 0x55 && fixture.last[33] == 0);

    /* PageCreated for that page goes through the drain; one for a page the
     * core does not know is fine and changes nothing. */
    uint8_t created[17] = { CREST_ENGINE_EVENT_PAGE_CREATED };
    memcpy(created + 1, page + 1, 16);
    assert(fixture.report(app, engine, created, sizeof(created)) == CREST_OK);
    assert(crest_app_drain(app, &buffer) == CREST_OK && buffer.bytes[0] == 1 && buffer.bytes[1] == CREST_CHANGE_PAGE_CHANGED);
    crest_buffer_free(&buffer);
    memset(created + 1, 0x77, 16);
    assert(crest_engine_report(app, engine, created, sizeof(created)) == CREST_OK);
    assert(crest_app_drain(app, &buffer) == CREST_OK && buffer.length == 1 && buffer.bytes[0] == 0);
    crest_buffer_free(&buffer);
    /* Bytes that do not decode, and handles that name no engine of this app. */
    const uint8_t garbage[] = { 0x7f, 0x01 };
    assert(crest_engine_report(app, engine, garbage, sizeof(garbage)) == CREST_INVALID_MESSAGE);
    assert(crest_engine_report(app, engine, created, sizeof(created) - 1) == CREST_INVALID_MESSAGE);
    assert(crest_engine_report(app, engine + 1000, created, sizeof(created)) == CREST_INVALID_HANDLE);
    assert(crest_engine_report(app + 1000, engine, created, sizeof(created)) == CREST_INVALID_HANDLE);

    assert(crest_engine_unregister(app, engine) == CREST_OK);
    assert(crest_engine_unregister(app, engine) == CREST_INVALID_HANDLE);
    assert(crest_engine_report(app, engine, created, sizeof(created)) == CREST_INVALID_HANDLE);
    assert(crest_session_destroy(session) == CREST_OK);
    assert(crest_app_destroy(app) == CREST_OK);
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
    uint64_t session = 0, access = 0, command = 0, request = 0;
    assert(crest_session_create((const uint8_t*)json, (size_t)size, &session) == CREST_OK);
    assert(crest_access_create(&access) == CREST_OK);
    assert(crest_session_attach_access(session, access + 1000) == CREST_INVALID_HANDLE);
    assert(crest_session_attach_access(session, access) == CREST_OK);
    assert(crest_session_attach_access(session, access) == CREST_OK);

    char edit[1024];
    size = snprintf(edit, sizeof(edit),
        "{\"version\":1,\"operation\":\"tab.move\",\"spaceId\":{\"rawValue\":\"%s\"},"
        "\"profileId\":\"%s\",\"now\":800000002,"
        "\"arguments\":{\"tabId\":\"%s\",\"placement\":\"saved\"},"
        "\"view\":{\"spaceId\":\"%s\","
        "\"tabs\":[{\"spaceId\":\"%s\",\"tabId\":\"%s\"}]}}",
        space_id, profile_id, tab_id, space_id, space_id, tab_id);
    assert(size > 0 && (size_t)size < sizeof(edit));
    assert(crest_session_prepare_command(session, (const uint8_t*)edit, (size_t)size, &command)
        == CREST_INVALID_MESSAGE && command == 0);

    uint8_t space[16], profile[16];
    memset(space, 0x44, sizeof(space)); memset(profile, 0x55, sizeof(profile));
    assert(crest_access_begin(access, space, profile, 1, &request) == CREST_OK && request != 0);
    assert(crest_access_complete(access, space, profile, request, 1) == CREST_OK);
    assert(crest_session_prepare_command(session, (const uint8_t*)edit, (size_t)size, &command) == CREST_OK
        && command != 0);
    assert(crest_session_release_command(command) == CREST_OK);

    assert(crest_access_lock_space(access, space) == CREST_OK);
    command = 0;
    assert(crest_session_prepare_command(session, (const uint8_t*)edit, (size_t)size, &command)
        == CREST_INVALID_MESSAGE && command == 0);
    assert(crest_access_destroy(access) == CREST_OK);
    assert(crest_session_destroy(session) == CREST_OK);
}
/* App-wide behavior preferences are session state; the launch plan reads the
 * saved startup choice from the session and is released without committing. */
static void preferences_boundary(void) {
    static const char* tab_id = "99999999-9999-4999-8999-999999999999";
    char json[1024];
    int size = snprintf(json, sizeof(json),
        "{\"selectedSpaceID\":{\"rawValue\":\"%s\"},\"spaces\":[{\"id\":{\"rawValue\":\"%s\"},"
        "\"profile\":{\"id\":\"%s\"},\"name\":\"Reading\","
        "\"tabs\":[{\"id\":{\"rawValue\":\"%s\"},\"title\":\"Page\",\"url\":\"https://example.com/\","
        "\"placement\":\"current\",\"lastActivatedAt\":800000000}"
        "],\"selectedTabID\":{\"rawValue\":\"%s\"},\"folders\":[],\"history\":[],\"archivedTabs\":[]}]}",
        space_id, space_id, profile_id, tab_id, tab_id);
    assert(size > 0 && (size_t)size < sizeof(json));
    uint64_t session = 0, command = 0, stale = 0;
    assert(crest_session_create((const uint8_t*)json, (size_t)size, &session) == CREST_OK);
    const char *set = "{\"version\":1,\"operation\":\"preferences.set\","
        "\"arguments\":{\"preference\":\"startupBehavior\",\"value\":\"lastActiveTab\"}}";
    assert(crest_session_prepare_command(session, (const uint8_t*)set, strlen(set), &command) == CREST_OK);
    assert(crest_session_prepare_command(session, (const uint8_t*)set, strlen(set), &stale) == CREST_OK);
    assert(crest_session_commit_command(command) == CREST_OK);
    assert(crest_session_release_command(command) == CREST_OK);
    /* A command prepared before another one committed is refused. */
    assert(crest_session_commit_command(stale) == CREST_INVALID_STATE);
    assert(crest_session_release_command(stale) == CREST_OK);
    const char *plan = "{\"version\":1,\"operation\":\"launch.plan\",\"platform\":\"desktop\",\"environment\":{"
        "\"testRuntime\":false,\"previewRuntime\":false,\"isolatedSession\":false,\"namedProfile\":false,"
        "\"isolatedCloudSync\":false,\"resetSession\":false,\"showcase\":false,\"inMemoryCredentials\":false,"
        "\"onboardingWelcome\":false,\"desktopSetup\":false,\"mobileSetup\":false,\"performanceHarness\":false,"
        "\"updateTestFeed\":false},\"hasActiveLaunchGate\":false}";
    assert(crest_session_prepare_command(session, (const uint8_t*)plan, strlen(plan), &command) == CREST_OK);
    char answer[512]; size_t length = 0;
    assert(crest_session_read_command(command, (uint8_t*)answer, sizeof(answer) - 1, &length) == CREST_OK);
    answer[length] = 0;
    assert(strstr(answer, "\"requiresIsolation\":false") && strstr(answer, "\"startupBehavior\":\"lastActiveTab\""));
    assert(crest_session_release_command(command) == CREST_OK);
    const char *unknown = "{\"version\":1,\"operation\":\"preferences.set\","
        "\"arguments\":{\"preference\":\"sidebarDensity\",\"value\":1}}";
    command = 0;
    assert(crest_session_prepare_command(session, (const uint8_t*)unknown, strlen(unknown), &command)
        != CREST_OK && command == 0);
    assert(crest_session_destroy(session) == CREST_OK);
}
/* The Quick Window site key is a typed query; borrowed-workspace command
 * routing is a core policy answer. */
static void links_boundary(void) {
    const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
    uint64_t app = 0;
    const uint8_t memory_only[] = { 0 };
    crest_buffer_t buffer = { NULL, 0 };
    assert(crest_app_create(fingerprint, sizeof(fingerprint), memory_only, sizeof(memory_only), &app, &buffer) == CREST_OK);
    /* QuickWindowSite: its tag, the address as a length-prefixed UTF-8 string,
     * then whether Quick Windows remember Spaces by site. */
    const char *url = "https://www.Docs.example.org/crest", *key = "docs.example.org";
    uint8_t site[64] = { CREST_QUERY_QUICK_WINDOW_SITE, (uint8_t)strlen(url) };
    memcpy(site + 2, url, strlen(url));
    site[2 + strlen(url)] = 1;
    assert(crest_app_query(app, site, 3 + strlen(url), &buffer) == CREST_OK);
    /* A present key: the presence byte, then the string. */
    assert(buffer.length == 2 + strlen(key) && buffer.bytes[0] == 1 && buffer.bytes[1] == strlen(key)
        && memcmp(buffer.bytes + 2, key, strlen(key)) == 0);
    crest_buffer_free(&buffer);
    assert(crest_app_destroy(app) == CREST_OK);
    uint8_t output[512]; size_t length = 0;
    const char *borrowed = "{\"version\":1,\"operation\":\"workspace.command_route\",\"command\":\"space.branding\",\"borrowed\":true}";
    assert(crest_core_evaluate_policy((const uint8_t*)borrowed, strlen(borrowed), output, sizeof(output) - 1, &length) == CREST_OK);
    output[length] = 0;
    assert(strstr((const char*)output, "\"route\":\"source\""));
}
static volatile int storage_wakes = 0;
static void count_wake(void* context) {
    assert(context == &storage_wakes);
    storage_wakes++;
}
/* AppConfiguration with a storage directory: presence, varint length, UTF-8. */
static size_t storage_configuration(const char* directory, uint8_t* output, size_t capacity) {
    size_t length = strlen(directory);
    assert(length < 128 && length + 2 <= capacity);
    output[0] = 1;
    output[1] = (uint8_t)length;
    memcpy(output + 2, directory, length);
    return length + 2;
}
/* A byte string: its LEB128 length, then the bytes. */
static size_t put_bytes(uint8_t* output, size_t at, size_t capacity, const char* bytes, size_t length) {
    size_t remaining = length;
    do {
        assert(at < capacity);
        uint8_t next = (uint8_t)(remaining & 0x7f);
        remaining >>= 7;
        output[at++] = remaining == 0 ? next : (uint8_t)(next | 0x80);
    } while (remaining != 0);
    assert(at + length <= capacity);
    memcpy(output + at, bytes, length);
    return at + length;
}
/* The core opens and owns session.sqlite: an empty file answers EMPTY, the
 * first session is adopted once, and the save it starts wakes the host. A
 * directory without a recovery checkpoint cannot be restored. */
static void storage_boundary(void) {
    const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
    /* The core creates the directory it is given. */
    char directory[96];
    snprintf(directory, sizeof(directory), "/tmp/crest-native-abi-%ld-%ld", (long)getpid(), (long)time(NULL));
    uint8_t configuration[160];
    size_t configured = storage_configuration(directory, configuration, sizeof(configuration));
    uint64_t app = 0, session = 0, sync = 0, projection = 0;
    crest_buffer_t buffer = { NULL, 0 };
    assert(crest_app_create(fingerprint, sizeof(fingerprint), configuration, configured, &app, &buffer) == CREST_OK && app != 0);
    assert(crest_app_session(app, &session, &sync, &projection) == CREST_EMPTY && session == 0);
    assert(crest_app_set_wake(app, count_wake, (void*)&storage_wakes) == CREST_OK);
    char json[512];
    int size = snprintf(json, sizeof(json),
        "{\"spaces\":[{\"id\":{\"rawValue\":\"%s\"},\"profile\":{\"id\":\"%s\"},\"name\":\"Stored\","
        "\"tabs\":[],\"folders\":[],\"history\":[],\"archivedTabs\":[]}]}", space_id, profile_id);
    assert(size > 0 && (size_t)size < sizeof(json));
    /* AdoptLegacySession: the installed release kept the session whole
     * (Core absent, WholeGraph present, no history parts, no journal), and the
     * same session is the seed. */
    uint8_t adoption[1100];
    size_t adopted = 0;
    adoption[adopted++] = CREST_INTENT_ADOPT_LEGACY_SESSION;
    adoption[adopted++] = 0;
    adoption[adopted++] = 1;
    adopted = put_bytes(adoption, adopted, sizeof(adoption), json, (size_t)size);
    adoption[adopted++] = 0;
    adoption[adopted++] = 0;
    adopted = put_bytes(adoption, adopted, sizeof(adoption), json, (size_t)size);
    assert(crest_app_dispatch(app, adoption, adopted, &buffer) == CREST_OK);
    /* Two changes: WorkspaceOpened for the session the file now holds, then
     * SessionAdopted, carrying no images. */
    assert(buffer.bytes[0] == 2 && buffer.bytes[1] == CREST_CHANGE_WORKSPACE_OPENED);
    assert(buffer.bytes[buffer.length - 2] == CREST_CHANGE_SESSION_ADOPTED && buffer.bytes[buffer.length - 1] == 0);
    crest_buffer_free(&buffer);
    /* The file holds a session now: a second adoption changes nothing. */
    assert(crest_app_dispatch(app, adoption, adopted, &buffer) == CREST_OK);
    assert(buffer.length == 1 && buffer.bytes[0] == 0);
    crest_buffer_free(&buffer);
    for (int attempt = 0; attempt < 1000 && storage_wakes == 0; attempt++) {
        struct timespec pause = { 0, 5000000 };
        nanosleep(&pause, NULL);
    }
    /* The core wakes the host for the save and for a turn: the launch stage
     * of the adopted session waits for the host to end its turn. */
    assert(storage_wakes >= 1);
    /* One change: Saved(Revision: 1), a tag and a little-endian int64. */
    int saved = 0;
    for (int attempt = 0; attempt < 1000 && !saved; attempt++) {
        assert(crest_app_drain(app, &buffer) == CREST_OK);
        saved = buffer.length == 10 && buffer.bytes[0] == 1 && buffer.bytes[1] == CREST_CHANGE_SAVED && buffer.bytes[2] == 1;
        assert(saved || (buffer.length == 1 && buffer.bytes[0] == 0));
        crest_buffer_free(&buffer);
        struct timespec pause = { 0, 5000000 };
        if (!saved) nanosleep(&pause, NULL);
    }
    assert(saved);
    /* Ending the turn starts the launch stage, which the host hears about. */
    assert(crest_app_end_turn(app) == CREST_OK);
    int staged = 0;
    for (int attempt = 0; attempt < 1000 && !staged; attempt++) {
        assert(crest_app_drain(app, &buffer) == CREST_OK);
        staged = buffer.length > 2 && buffer.bytes[0] == 1 && buffer.bytes[1] == CREST_CHANGE_SYNC_JOURNAL_CHANGED;
        assert(staged || (buffer.length == 1 && buffer.bytes[0] == 0));
        crest_buffer_free(&buffer);
        struct timespec pause = { 0, 5000000 };
        if (!staged) nanosleep(&pause, NULL);
    }
    assert(staged);
    assert(crest_app_set_wake(app, NULL, NULL) == CREST_OK);
    assert(crest_app_session(app, &session, &sync, &projection) == CREST_OK && session != 0);
    /* The stored session's workspace, which a saved window shows. */
    uint8_t workspace[16] = { 0 }, again[16] = { 0 };
    assert(crest_session_attach_device(session, app, workspace) == CREST_OK);
    assert(crest_session_attach_device(session, app, again) == CREST_OK && memcmp(workspace, again, 16) == 0);
    /* OpenWindow: its tag, the window, the workspace, Saved, no window to copy,
     * no Space to show, no tabs to show, RestoresTabs. It answers one
     * WindowChanged. */
    uint8_t opening[38] = { CREST_INTENT_OPEN_WINDOW };
    memset(opening + 1, 0x42, 16);
    memcpy(opening + 17, workspace, 16);
    opening[33] = 1; opening[34] = 0; opening[35] = 0; opening[36] = 0; opening[37] = 1;
    assert(crest_app_dispatch(app, opening, sizeof(opening), &buffer) == CREST_OK);
    assert(buffer.length > 2 && buffer.bytes[0] == 1 && buffer.bytes[1] == CREST_CHANGE_WINDOW_CHANGED);
    crest_buffer_free(&buffer);
    assert(crest_session_release_command(projection) == CREST_OK);
    assert(crest_sync_authority_release(sync) == CREST_OK);
    assert(crest_session_destroy(session) == CREST_OK);
    assert(crest_app_destroy(app) == CREST_OK);

    /* A second launch loads what the first one saved. */
    assert(crest_app_create(fingerprint, sizeof(fingerprint), configuration, configured, &app, &buffer) == CREST_OK);
    assert(crest_app_session(app, &session, &sync, &projection) == CREST_OK && session != 0);
    assert(crest_session_release_command(projection) == CREST_OK);
    assert(crest_sync_authority_release(sync) == CREST_OK);
    assert(crest_session_destroy(session) == CREST_OK);
    assert(crest_app_destroy(app) == CREST_OK);

    /* A file that is not a session is refused with a rejection, untouched. */
    char path[256];
    snprintf(path, sizeof(path), "%s/session.sqlite", directory);
    FILE* file = fopen(path, "wb");
    assert(file != NULL && fputs("not a session", file) >= 0 && fclose(file) == 0);
    assert(crest_app_create(fingerprint, sizeof(fingerprint), configuration, configured, &app, &buffer) == CREST_REJECTED
        && app == 0 && buffer.bytes != NULL && buffer.bytes[0] == CREST_REJECTION_STORAGE_UNREADABLE);
    crest_buffer_free(&buffer);
    /* The second launch kept a recovery checkpoint, since the file held a
     * session and its staged journal; without one a restore is refused. */
    char checkpoint[256];
    snprintf(checkpoint, sizeof(checkpoint), "%s/session.recovery.sqlite", directory);
    assert(remove(checkpoint) == 0);
    assert(crest_app_restore(fingerprint, sizeof(fingerprint), configuration, configured, &buffer) == CREST_REJECTED
        && buffer.bytes != NULL && buffer.bytes[0] == CREST_REJECTION_RECOVERY_CHECKPOINT_UNUSABLE);
    crest_buffer_free(&buffer);
    char command[320];
    snprintf(command, sizeof(command), "rm -rf '%s'", directory);
    assert(system(command) == 0);
}
int main(void) {
    assert(crest_core_abi_version() == CREST_ABI_VERSION);
    policy_boundary();
    links_boundary();
    access_boundary();
    app_boundary();
    permissions_boundary();
    session_boundary();
    engine_boundary();
    storage_boundary();
    locked_space_boundary();
    preferences_boundary();
    puts("Native ABI buffer ownership, size retry, handle, session, engine and lock checks passed.");
    return 0;
}

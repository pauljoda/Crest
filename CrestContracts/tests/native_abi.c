#include "crest_app.h"
#include "crest_contracts.h"
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
static void app_boundary(void) {
    const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
    uint8_t stale[CREST_CONTRACTS_FINGERPRINT_LENGTH];
    memcpy(stale, fingerprint, sizeof(stale)); stale[0] ^= 1;
    uint64_t app = 0;
    crest_buffer_t buffer = { (uint8_t*)1, 1 };
    assert(crest_app_create(stale, sizeof(stale), &app) == CREST_VERSION_MISMATCH && app == 0);
    assert(crest_app_create(fingerprint, sizeof(fingerprint), &app) == CREST_OK && app != 0);
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
    /* Window repair answers from presence facts; a captured empty Space stays empty. */
    const char *window = "{\"version\":1,\"operation\":\"window.repair\",\"selectedSpaceID\":\"66666666-6666-6666-6666-666666666666\","
        "\"capturesSelection\":true,"
        "\"spaces\":[{\"id\":\"44444444-4444-4444-4444-444444444444\",\"windowTab\":false,\"captured\":true,"
        "\"hasTabs\":true}],\"splitLayouts\":[]}";
    assert(crest_core_evaluate_policy((const uint8_t*)window, strlen(window), output, 256, &length) == CREST_OK);
    output[length] = 0;
    assert(strstr((const char*)output, "\"selectedSpaceID\":\"44444444-4444-4444-4444-444444444444\"")
        && strstr((const char*)output, "\"selections\":[\"none\"]"));
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
        "\"implementationVersion\":\"1\",\"protocolVersion\":%u,\"capabilities\":{\"pages\":%s,\"navigation\":%s,"
        "\"workspace-profiles\":%s,\"profile-deletion\":%s}}",
        CREST_PROTOCOL_VERSION, capability, capability, capability, capability);
    assert(size > 0 && (size_t)size < sizeof(engine));
    assert(crest_session_register_engine(session + 1000, (const uint8_t*)engine, (size_t)size) == CREST_INVALID_HANDLE);
    assert(crest_session_register_engine(session, (const uint8_t*)engine, (size_t)size) == CREST_OK);
    assert(crest_session_register_engine(session, (const uint8_t*)engine, (size_t)size) == CREST_INVALID_MESSAGE);
    memset(engine, 0xaa, sizeof(engine)); /* The session must own its descriptor copy. */

    /* Selection is window state: the checkpoint takes none and a legacy
     * session-level selection in the input document is not written back. */
    uint64_t checkpoint = 0;
    assert(crest_session_checkpoint(session, revision + 1, &checkpoint) == CREST_INVALID_STATE && checkpoint == 0);
    assert(crest_session_checkpoint(session, revision, &checkpoint) == CREST_OK && checkpoint != 0);

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
    assert(strstr((const char*)output, "selectedSpaceID") == NULL);
    free(output);

    assert(crest_session_release_checkpoint(checkpoint) == CREST_OK);
    assert(crest_session_release_checkpoint(checkpoint) == CREST_INVALID_HANDLE);
    assert(crest_session_destroy(session) == CREST_OK);
    assert(crest_session_destroy(session) == CREST_INVALID_HANDLE);
    assert(crest_session_checkpoint(session, 1, &checkpoint) == CREST_INVALID_HANDLE);
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
        "\"view\":{\"spaceId\":\"%s\","
        "\"tabs\":[{\"spaceId\":\"%s\",\"tabId\":\"%s\"}]}}",
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
    uint64_t session = 0, revision = 0, command = 0, accepted = 0;
    assert(crest_session_create((const uint8_t*)json, (size_t)size, &session, &revision) == CREST_OK);
    const char *set = "{\"version\":1,\"operation\":\"preferences.set\","
        "\"arguments\":{\"preference\":\"startupBehavior\",\"value\":\"lastActiveTab\"}}";
    assert(crest_session_prepare_command(session, revision, (const uint8_t*)set, strlen(set), &command) == CREST_OK);
    assert(crest_session_commit_command(command, &accepted) == CREST_OK && accepted == revision + 1);
    assert(crest_session_release_command(command) == CREST_OK);
    const char *plan = "{\"version\":1,\"operation\":\"launch.plan\",\"platform\":\"desktop\",\"environment\":{"
        "\"testRuntime\":false,\"previewRuntime\":false,\"isolatedSession\":false,\"namedProfile\":false,"
        "\"isolatedCloudSync\":false,\"resetSession\":false,\"showcase\":false,\"inMemoryCredentials\":false,"
        "\"onboardingWelcome\":false,\"desktopSetup\":false,\"mobileSetup\":false,\"performanceHarness\":false,"
        "\"updateTestFeed\":false},\"hasActiveLaunchGate\":false}";
    assert(crest_session_prepare_command(session, accepted, (const uint8_t*)plan, strlen(plan), &command) == CREST_OK);
    char answer[512]; size_t length = 0;
    assert(crest_session_read_command(command, (uint8_t*)answer, sizeof(answer) - 1, &length) == CREST_OK);
    answer[length] = 0;
    assert(strstr(answer, "\"requiresIsolation\":false") && strstr(answer, "\"startupBehavior\":\"lastActiveTab\""));
    assert(crest_session_release_command(command) == CREST_OK);
    const char *unknown = "{\"version\":1,\"operation\":\"preferences.set\","
        "\"arguments\":{\"preference\":\"sidebarDensity\",\"value\":1}}";
    command = 0;
    assert(crest_session_prepare_command(session, accepted, (const uint8_t*)unknown, strlen(unknown), &command)
        != CREST_OK && command == 0);
    assert(crest_session_destroy(session) == CREST_OK);
}
/* Link routing and borrowed-workspace command routing are core policy answers. */
static void links_boundary(void) {
    const char *route = "{\"version\":1,\"operation\":\"links.route\",\"url\":\"https://docs.example.org/crest\","
        "\"routes\":[{\"id\":\"66666666-6666-4666-8666-666666666666\",\"isEnabled\":true,\"match\":\"contains\","
        "\"pattern\":\"EXAMPLE.org\",\"destinationSpaceID\":\"77777777-7777-4777-8777-777777777777\"}],"
        "\"destination\":\"quickWindow\",\"chosenSpaceID\":null,\"remembersSpaceBySite\":true,\"rememberedSpaceID\":null,"
        "\"spaces\":[\"88888888-8888-4888-8888-888888888888\",\"77777777-7777-4777-8777-777777777777\"],"
        "\"selectedSpaceID\":\"88888888-8888-4888-8888-888888888888\",\"unavailableSpaceIDs\":[]}";
    uint8_t output[512]; size_t length = 0;
    assert(crest_core_evaluate_policy((const uint8_t*)route, strlen(route), output, sizeof(output) - 1, &length) == CREST_OK);
    output[length] = 0;
    assert(strstr((const char*)output, "\"quickWindow\":false") && strstr((const char*)output, "77777777-7777-4777-8777-777777777777"));
    const char *borrowed = "{\"version\":1,\"operation\":\"workspace.command_route\",\"command\":\"space.branding\",\"borrowed\":true}";
    assert(crest_core_evaluate_policy((const uint8_t*)borrowed, strlen(borrowed), output, sizeof(output) - 1, &length) == CREST_OK);
    output[length] = 0;
    assert(strstr((const char*)output, "\"route\":\"source\""));
}
int main(void) {
    assert(crest_core_abi_version() == CREST_ABI_VERSION);
    policy_boundary();
    links_boundary();
    access_boundary();
    app_boundary();
    permissions_boundary();
    session_boundary();
    locked_space_boundary();
    preferences_boundary();
    puts("Native ABI buffer ownership, size retry, handle, session and lock checks passed.");
    return 0;
}

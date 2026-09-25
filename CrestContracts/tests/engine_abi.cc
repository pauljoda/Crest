// A C++ engine binding against the actual core library, through the generated
// C++ codec alone: it registers with the codec's fingerprint, decodes the
// commands the core issues and reports every engine event the core reads.
// Chromium's binding speaks the same codec, so this proves the two agree
// without building Chromium.
#include "crest_app.h"
#include "crest_contracts.h"
#include "crest_engine.h"
#include "crest_engine_contract.h"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <variant>
#include <vector>

namespace {

namespace engine = crest::engine;

// A binding under test: what attach handed it and the commands it ran.
struct Binding {
  uint64_t app = 0;
  uint64_t engine = 0;
  crest_engine_report_t report = nullptr;
  std::vector<engine::EngineCommand> commands;
};

void CREST_CALL Attach(void* context, uint64_t app, uint64_t engine_handle, crest_engine_report_t report) {
  auto* binding = static_cast<Binding*>(context);
  binding->app = app;
  binding->engine = engine_handle;
  binding->report = report;
}

void CREST_CALL Run(void* context, const uint8_t* bytes, size_t length) {
  auto command = engine::Decode<engine::EngineCommand>(bytes, length);
  assert(command.has_value());
  static_cast<Binding*>(context)->commands.push_back(std::move(*command));
}

crest_status_t Report(const Binding& binding, const engine::EngineEvent& event) {
  const std::vector<uint8_t> bytes = engine::Encode(event);
  return binding.report(binding.app, binding.engine, bytes.data(), bytes.size());
}

engine::Guid Filled(uint8_t value) {
  engine::Guid guid;
  guid.fill(value);
  return guid;
}

std::vector<uint8_t> Drained(uint64_t app) {
  crest_buffer_t buffer = {nullptr, 0};
  assert(crest_app_drain(app, &buffer) == CREST_OK);
  std::vector<uint8_t> bytes(buffer.bytes, buffer.bytes + buffer.length);
  crest_buffer_free(&buffer);
  return bytes;
}

std::vector<uint8_t> Dispatched(uint64_t app, const std::vector<uint8_t>& intent) {
  crest_buffer_t buffer = {nullptr, 0};
  assert(crest_app_dispatch(app, intent.data(), intent.size(), &buffer) == CREST_OK);
  std::vector<uint8_t> bytes(buffer.bytes, buffer.bytes + buffer.length);
  crest_buffer_free(&buffer);
  return bytes;
}

// A fixed set member or an enum of the application contract, which the
// engine codec does not name: its tag.
struct Member {
  uint32_t tag;
};
void Write(engine::WireWriter& writer, Member member) { writer.WriteVarint(member.tag); }

// An intent spelled with the codec's writer: its tag, then its fields.
template <typename... Fields>
std::vector<uint8_t> Intent(uint32_t tag, const Fields&... fields) {
  using engine::Write;
  engine::WireWriter writer;
  writer.WriteVarint(tag);
  (Write(writer, fields), ...);
  return writer.Take();
}

// Every event the core reads survives the codec unchanged, and a message
// that is cut short, runs on, or holds a string that is not UTF-8 decodes to
// nothing.
void CodecRoundTrips() {
  const engine::Guid page = Filled(0x61);
  const std::vector<engine::EngineEvent> events = {
      engine::NavigationCommitted{.page_id = page, .url = "https://example.com/a", .same_document = true},
      engine::NavigationFailed{.page_id = page,
                               .failure = {.error = engine::NavigationError::kCannotFindServer,
                                           .url = "https://missing.example/",
                                           .replaced_document = true,
                                           .domain = "net",
                                           .code = -105}},
      engine::NavigationFinished{.page_id = page, .url = "https://example.com/a", .title = "Caf\xc3\xa9"},
      engine::NavigationStarted{.page_id = page, .url = "https://example.com/b"},
      engine::PageClosed{.page_id = page},
      engine::PageCreated{.page_id = page},
      engine::PageCreationFailed{.page_id = page},
      engine::PageIconChanged{.page_id = page, .url = "https://example.com/", .accent = engine::TabIconAccent{0.25, 0.5, 1}},
      engine::PageStateChanged{.page_id = page,
                               .snapshot = {.url = "https://example.com/",
                                            .pending_url = std::nullopt,
                                            .title = "Example",
                                            .is_loading = true,
                                            .can_go_back = true,
                                            .security = engine::PageSecurity::kMixedContent,
                                            .media = engine::PageMediaActivity::kPlaying |
                                                     engine::PageMediaActivity::kPictureInPicture}},
  };
  for (size_t tag = 0; tag < events.size(); ++tag) {
    assert(events[tag].index() == tag);
    std::vector<uint8_t> bytes = engine::Encode(events[tag]);
    assert(bytes[0] == tag);
    assert(engine::Decode<engine::EngineEvent>(bytes.data(), bytes.size()) == events[tag]);
    assert(!engine::Decode<engine::EngineEvent>(bytes.data(), bytes.size() - 1));
    bytes.push_back(0);
    assert(!engine::Decode<engine::EngineEvent>(bytes.data(), bytes.size()));
  }
  std::vector<uint8_t> finished = engine::Encode(events[2]);
  finished[finished.size() - 2] = 0xff;  // The title's é, no longer UTF-8.
  assert(!engine::Decode<engine::EngineEvent>(finished.data(), finished.size()));
  const uint8_t overlong[] = {0x80, 0x00};
  assert(!engine::Decode<engine::EngineEvent>(overlong, sizeof(overlong)));
  const uint8_t unknown[] = {CREST_ENGINE_EVENT_PAGE_STATE_CHANGED + 1};
  assert(!engine::Decode<engine::EngineEvent>(unknown, sizeof(unknown)));
}

void EngineBoundary() {
  const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
  const uint8_t engine_fingerprint[CREST_ENGINE_CONTRACT_FINGERPRINT_LENGTH] = CREST_ENGINE_CONTRACT_FINGERPRINT;
  static_assert(sizeof(engine_fingerprint) == engine::kFingerprint.size());
  assert(std::memcmp(engine_fingerprint, engine::kFingerprint.data(), sizeof(engine_fingerprint)) == 0);
  // AppConfiguration(StorageDirectory: null, Platform: Desktop).
  const uint8_t memory_only[] = {0, 0};
  uint64_t app = 0;
  crest_buffer_t buffer = {nullptr, 0};
  assert(crest_app_create(fingerprint, sizeof(fingerprint), memory_only, sizeof(memory_only), &app, &buffer) == CREST_OK);

  Binding binding;
  const crest_engine_binding_t table = {&binding, Attach, Run};
  const std::vector<uint8_t> registration = engine::Encode(engine::EngineRegistration{
      .kind = engine::EngineKind::kChromium,
      .capabilities = {engine::EngineCapability::kPages, engine::EngineCapability::kNavigation,
                       engine::EngineCapability::kWorkspaceProfiles, engine::EngineCapability::kProfileDeletion},
      .is_default = true});
  uint64_t handle = 0;
  assert(crest_engine_register(app, engine::kFingerprint.data(), engine::kFingerprint.size(), registration.data(),
                               registration.size(), &table, &handle, &buffer) == CREST_OK);
  assert(handle != 0 && binding.engine == handle && binding.app == app && binding.report == crest_engine_report);
  Drained(app);

  // A workspace opened from a seed, with a window open over it.
  const char* space_id = "44444444-4444-4444-4444-444444444444";
  const char* profile_id = "55555555-5555-5555-5555-555555555555";
  char json[1024];
  const int size = std::snprintf(json, sizeof(json),
      "{\"spaces\":[{\"id\":{\"rawValue\":\"%s\"},\"profile\":{\"id\":\"%s\"},\"name\":\"Reading\",\"tabs\":[],"
      "\"folders\":[],\"history\":[],\"archivedTabs\":[]}]}", space_id, profile_id);
  assert(size > 0 && static_cast<size_t>(size) < sizeof(json));
  // OpenWorkspace: WorkspaceKind.Persistent, then the seed as a byte string.
  const std::vector<uint8_t> opened = Dispatched(app, Intent(CREST_INTENT_OPEN_WORKSPACE, Member{0},
      std::optional<engine::Bytes>(engine::Bytes(json, json + size))));
  assert(opened[0] == 1 && opened[1] == CREST_CHANGE_WORKSPACE_OPENED);
  engine::Guid workspace;
  std::memcpy(workspace.data(), opened.data() + 2, 16);
  const engine::Guid window = Filled(0x42);
  // OpenWindow: not saved, nothing to copy or show, no tabs, RestoresTabs.
  Dispatched(app, Intent(CREST_INTENT_OPEN_WINDOW, window, workspace, false, std::optional<engine::Guid>(),
                         std::optional<engine::Guid>(), std::vector<engine::Guid>(), true));

  // OpenPage for a transient request: the binding creates it in its window.
  const engine::Guid page = Filled(0x61);
  Dispatched(app, Intent(CREST_INTENT_OPEN_PAGE, page, workspace, Filled(0x44), std::optional<engine::Guid>(), window));
  assert(binding.commands.size() == 1);
  const auto& creation = std::get<engine::CreatePage>(binding.commands[0]);
  assert(creation.page_id == page && creation.profile_id == Filled(0x55) && !creation.is_private &&
         creation.window_id == window);

  // Every event the binding reports decodes in the core.
  assert(Report(binding, engine::PageCreated{.page_id = page}) == CREST_OK);
  Dispatched(app, Intent(CREST_INTENT_NAVIGATE, page, std::string("https://example.com/")));
  assert(binding.commands.size() == 2);
  assert(std::get<engine::LoadPage>(binding.commands[1]).url == "https://example.com/");
  const std::string url = "https://example.com/";
  assert(Report(binding, engine::NavigationStarted{.page_id = page, .url = url}) == CREST_OK);
  assert(Report(binding, engine::NavigationCommitted{.page_id = page, .url = url}) == CREST_OK);
  assert(Report(binding, engine::PageStateChanged{
      .page_id = page, .snapshot = {.url = url, .title = "Example", .security = engine::PageSecurity::kSecure}}) == CREST_OK);
  assert(Report(binding, engine::PageIconChanged{.page_id = page, .url = url, .accent = engine::TabIconAccent{1, 0, 0}}) ==
         CREST_OK);
  assert(Report(binding, engine::NavigationFinished{.page_id = page, .url = url, .title = "Example"}) == CREST_OK);
  assert(Report(binding, engine::NavigationFailed{
      .page_id = page, .failure = {.error = engine::NavigationError::kOffline, .url = url, .domain = "net", .code = -106}}) ==
      CREST_OK);
  const std::vector<uint8_t> drained = Drained(app);
  assert(!drained.empty() && drained[0] > 0);
  // The page's release closes what the engine holds.
  Dispatched(app, Intent(CREST_INTENT_RELEASE_PAGE, page, false));
  assert(binding.commands.size() == 3);
  assert(std::get<engine::ClosePage>(binding.commands[2]) == (engine::ClosePage{.page_id = page}));
  assert(Report(binding, engine::PageClosed{.page_id = page}) == CREST_OK);

  // A report that does not decode is malformed, never a rejection.
  const uint8_t garbage[] = {0x7f, 0x01};
  assert(binding.report(app, handle, garbage, sizeof(garbage)) == CREST_INVALID_MESSAGE);
  assert(crest_engine_unregister(app, handle) == CREST_OK);
  assert(crest_app_destroy(app) == CREST_OK);
}

}  // namespace

int main() {
  CodecRoundTrips();
  EngineBoundary();
  std::puts("C++ engine codec and binding checks passed.");
  return 0;
}

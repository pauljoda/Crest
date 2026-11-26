#include "chrome/browser/ui/crest/crest_core_library.h"

#include <memory>

#include "base/logging.h"

namespace crest {

namespace {

template <typename Function>
bool Resolve(base::NativeLibrary library, const char* name, Function* function) {
  *function = reinterpret_cast<Function>(base::GetFunctionPointerFromNativeLibrary(library, name));
  if (!*function) LOG(ERROR) << "The native core exports no " << name;
  return *function != nullptr;
}

}  // namespace

// static
std::unique_ptr<CoreLibrary> CoreLibrary::Load(const base::FilePath& path) {
  base::NativeLibraryLoadError error;
  base::NativeLibrary library = base::LoadNativeLibrary(path, &error);
  if (!library) {
    LOG(ERROR) << "Cannot load the native core at " << path << ": " << error.ToString();
    return nullptr;
  }
  std::unique_ptr<CoreLibrary> core(new CoreLibrary());
  core->library_ = library;
  const bool resolved = Resolve(library, "crest_core_abi_version", &core->abi_version_) &&
                        Resolve(library, "crest_app_create", &core->create_) &&
                        Resolve(library, "crest_app_dispatch", &core->dispatch_) &&
                        Resolve(library, "crest_app_query", &core->query_) &&
                        Resolve(library, "crest_app_drain", &core->drain_) &&
                        Resolve(library, "crest_app_end_turn", &core->end_turn_) &&
                        Resolve(library, "crest_app_set_wake", &core->set_wake_) &&
                        Resolve(library, "crest_buffer_free", &core->buffer_free_) &&
                        Resolve(library, "crest_engine_register", &core->engine_register_);
  if (!resolved) return nullptr;
  if (core->abi_version_() != CREST_ABI_VERSION) {
    LOG(ERROR) << "The native core speaks ABI " << core->abi_version_() << ", not " << CREST_ABI_VERSION;
    return nullptr;
  }
  return core;
}

// The library stays loaded until the process exits: crest_core.h forbids
// unloading a Native AOT library.
CoreLibrary::~CoreLibrary() = default;

std::vector<uint8_t> CoreLibrary::Take(crest_buffer_t& buffer) {
  std::vector<uint8_t> bytes;
  if (buffer.bytes && buffer.length) bytes.assign(buffer.bytes, buffer.bytes + buffer.length);
  if (buffer.bytes) buffer_free_(&buffer);
  return bytes;
}

CoreReply CoreLibrary::Create(const std::vector<uint8_t>& fingerprint, const std::vector<uint8_t>& configuration,
                              uint64_t* app) {
  crest_buffer_t rejection{};
  CoreReply reply;
  reply.status = create_(fingerprint.data(), fingerprint.size(), configuration.data(), configuration.size(), app,
                         &rejection);
  reply.bytes = Take(rejection);
  return reply;
}

CoreReply CoreLibrary::Dispatch(uint64_t app, const std::vector<uint8_t>& intent) {
  crest_buffer_t output{};
  CoreReply reply;
  reply.status = dispatch_(app, intent.data(), intent.size(), &output);
  reply.bytes = Take(output);
  return reply;
}

CoreReply CoreLibrary::Query(uint64_t app, const std::vector<uint8_t>& query) {
  crest_buffer_t output{};
  CoreReply reply;
  reply.status = query_(app, query.data(), query.size(), &output);
  reply.bytes = Take(output);
  return reply;
}

CoreReply CoreLibrary::Drain(uint64_t app) {
  crest_buffer_t output{};
  CoreReply reply;
  reply.status = drain_(app, &output);
  reply.bytes = Take(output);
  return reply;
}

crest_status_t CoreLibrary::EndTurn(uint64_t app) {
  return end_turn_(app);
}

crest_status_t CoreLibrary::SetWake(uint64_t app, crest_wake_t wake, void* context) {
  return set_wake_(app, wake, context);
}

CoreReply CoreLibrary::RegisterEngine(uint64_t app, const std::vector<uint8_t>& fingerprint,
                                      const std::vector<uint8_t>& registration,
                                      const crest_engine_binding_t& binding, uint64_t* engine) {
  crest_buffer_t rejection{};
  CoreReply reply;
  reply.status = engine_register_(app, fingerprint.data(), fingerprint.size(), registration.data(),
                                  registration.size(), &binding, engine, &rejection);
  reply.bytes = Take(rejection);
  return reply;
}

}  // namespace crest

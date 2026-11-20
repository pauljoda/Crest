#ifndef CHROME_BROWSER_UI_CREST_CREST_CORE_LIBRARY_H_
#define CHROME_BROWSER_UI_CREST_CREST_CORE_LIBRARY_H_

#include <cstdint>
#include <memory>
#include <vector>

#include "base/files/file_path.h"
#include "base/native_library.h"
#include "chrome/browser/ui/crest/crest_engine.h"

namespace crest {

// What a call into the core answered: its status and the bytes it returned,
// the contract wire format the interface reads.
struct CoreReply {
  crest_status_t status = CREST_INTERNAL_ERROR;
  std::vector<uint8_t> bytes;
};

// The native core, CrestCore.Native, which ships beside the engine rather than
// in it: the desktop shell loads it at run time, so the engine never links a
// particular build of the core and a core change needs no new engine.
class CoreLibrary {
 public:
  // Loads the library at `path`, or nothing when it is missing or speaks
  // another ABI.
  static std::unique_ptr<CoreLibrary> Load(const base::FilePath& path);

  CoreLibrary(const CoreLibrary&) = delete;
  CoreLibrary& operator=(const CoreLibrary&) = delete;
  ~CoreLibrary();

  CoreReply Create(const std::vector<uint8_t>& fingerprint, const std::vector<uint8_t>& configuration,
                   uint64_t* app);
  CoreReply Dispatch(uint64_t app, const std::vector<uint8_t>& intent);
  CoreReply Query(uint64_t app, const std::vector<uint8_t>& query);
  CoreReply Drain(uint64_t app);
  crest_status_t EndTurn(uint64_t app);
  crest_status_t SetWake(uint64_t app, crest_wake_t wake, void* context);
  CoreReply RegisterEngine(uint64_t app, const std::vector<uint8_t>& fingerprint,
                           const std::vector<uint8_t>& registration, const crest_engine_binding_t& binding,
                           uint64_t* engine);

 private:
  CoreLibrary() = default;

  // The bytes `buffer` holds, copied, after which the core frees it.
  std::vector<uint8_t> Take(crest_buffer_t& buffer);

  base::NativeLibrary library_ = nullptr;
  uint32_t (CREST_CALL* abi_version_)() = nullptr;
  crest_status_t (CREST_CALL* create_)(const uint8_t*, size_t, const uint8_t*, size_t, uint64_t*, crest_buffer_t*) = nullptr;
  crest_status_t (CREST_CALL* dispatch_)(uint64_t, const uint8_t*, size_t, crest_buffer_t*) = nullptr;
  crest_status_t (CREST_CALL* query_)(uint64_t, const uint8_t*, size_t, crest_buffer_t*) = nullptr;
  crest_status_t (CREST_CALL* drain_)(uint64_t, crest_buffer_t*) = nullptr;
  crest_status_t (CREST_CALL* end_turn_)(uint64_t) = nullptr;
  crest_status_t (CREST_CALL* set_wake_)(uint64_t, crest_wake_t, void*) = nullptr;
  void (CREST_CALL* buffer_free_)(crest_buffer_t*) = nullptr;
  crest_status_t (CREST_CALL* engine_register_)(uint64_t, const uint8_t*, size_t, const uint8_t*, size_t,
                                                const crest_engine_binding_t*, uint64_t*, crest_buffer_t*) = nullptr;
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_CORE_LIBRARY_H_

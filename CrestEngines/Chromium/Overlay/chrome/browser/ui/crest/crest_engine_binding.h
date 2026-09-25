#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_BINDING_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_BINDING_H_

#include <array>
#include <cstdint>
#include <deque>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback_forward.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "chrome/browser/ui/crest/crest_engine.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"

class GURL;

namespace content {
class WebContents;
}

namespace crest {

class EnginePage;

// Chromium's engine binding: the portable half of Crest's Chromium host, in
// C++ and Chromium's own types with no Objective-C, so it serves every
// platform. It implements crest_engine.h. The core hands it commands through
// the table's `run` and it reports what the engine does with each page
// straight to the core, through the function `attach` gave it. Each
// platform's shell embeds the pages' views and does what only the operating
// system can.
//
// Everything runs on Chromium's UI thread. The core delivers the commands a
// report causes before the report returns, and a command such as ClosePage
// must never destroy a WebContents inside one of its own observers, so no
// report is made on the stack of a Chromium callback: reports queue, and one
// task posted to the UI thread sends them in order. A page's snapshot is sent
// last in the turn in which it changed.
class EngineBinding {
 public:
  // What the platform shell still does for the binding. TRANSITIONAL: the
  // shell keeps the engine profiles, the Browsers and the pages' media
  // sessions until those areas move into the binding.
  class Shell {
   public:
    virtual ~Shell() = default;
    // Creates `page`'s WebContents in the engine profile of `profile`, inside
    // the Browser of `window`, and answers it, or nullptr when it cannot. The
    // shell attaches its own presentation to the WebContents but tells no one
    // yet.
    virtual void CreateContents(const std::string& page,
                                const std::string& profile,
                                bool is_private,
                                const std::string& window,
                                base::OnceCallback<void(content::WebContents*)> created) = 0;
    // Makes the WebContents the engine offered as `token` the page, when it is
    // in `profile`, and answers it, or nullptr when the offer is gone.
    virtual content::WebContents* AdoptContents(const std::string& page,
                                                const std::string& token,
                                                const std::string& profile) = 0;
    // The binding follows `page`'s new WebContents: the platform may now
    // present it, before the page loads anything.
    virtual void ContentsCreated(const std::string& page) = 0;
    // The binding could not create `page`.
    virtual void CreationFailed(const std::string& page) = 0;
    // Destroys `page`'s WebContents, which the binding has let go of.
    virtual void DestroyContents(const std::string& page) = 0;
    // Loads the link navigation staged as `token` in `page`, which is heading
    // to `url`. TRANSITIONAL until link routing moves into the core (WP C (l)).
    virtual bool LoadStagedNavigation(const std::string& page, const std::string& token, const GURL& url) = 0;
    virtual void DiscardStagedNavigation(const std::string& token) = 0;
    // What media `page` runs. TRANSITIONAL until the media session moves.
    virtual engine::PageMediaActivity MediaActivity(const std::string& page) = 0;
  };

  static EngineBinding& Get();

  EngineBinding(const EngineBinding&) = delete;
  EngineBinding& operator=(const EngineBinding&) = delete;

  // The function table the platform registers with the core, and the engine
  // contract the binding was built against, which the core checks.
  crest_engine_binding_t Table();
  static const std::array<uint8_t, 32>& Fingerprint();

  void SetShell(Shell* shell);
  // The engine is shutting down: nothing more is reported, and every page is
  // let go of without a report.
  void Dispose();

  // What the platform asks of a page directly. TRANSITIONAL routes until the
  // generated PageRequest path replaces them.
  bool Adopt(const std::string& page, const std::string& token);
  bool Stage(const std::string& page, const std::string& token, const std::string& url);
  void Load(const std::string& page, const std::string& url);
  bool Restore(const std::string& page, std::vector<uint8_t> state, const std::string& expected_url);
  std::optional<std::vector<uint8_t>> SaveInteractionState(const std::string& page);
  std::optional<std::vector<uint8_t>> Icon(const std::string& page);
  // What `page` shows changed in a way only the shell sees, such as its media
  // session.
  void StateChanged(const std::string& page);

  // For the binding's pages.
  void Report(engine::EngineEvent event);
  void ReportStateSoon(const std::string& page);
  void PageLost(const std::string& page);
  bool LoadStagedNavigation(const std::string& page, const std::string& token, const GURL& url);
  void DiscardStagedNavigation(const std::string& token);
  engine::PageMediaActivity MediaActivity(const std::string& page);

 private:
  friend class base::NoDestructor<EngineBinding>;

  EngineBinding();
  ~EngineBinding();

  static void CREST_CALL Attach(void* context, uint64_t app, uint64_t engine, crest_engine_report_t report);
  static void CREST_CALL Run(void* context, const uint8_t* command, size_t length);

  void Handle(engine::EngineCommand command);
  void Create(const engine::CreatePage& creation);
  void CreateNow(const std::string& page);
  void Created(const std::string& page, content::WebContents* contents);
  void Live(EnginePage& page, content::WebContents* contents);
  void Close(const engine::ClosePage& closing);
  void Forget(const std::string& page);
  void ScheduleFlush();
  void Flush();
  EnginePage* Find(const std::string& page);

  raw_ptr<Shell> shell_ = nullptr;
  uint64_t app_ = 0;
  uint64_t engine_ = 0;
  crest_engine_report_t report_ = nullptr;
  bool disposing_ = false;
  std::map<std::string, std::unique_ptr<EnginePage>> pages_;
  std::deque<engine::EngineEvent> queue_;
  std::vector<std::string> due_;
  bool flush_posted_ = false;
  bool flushing_ = false;
  base::WeakPtrFactory<EngineBinding> weak_factory_{this};
};

// A GUID as the platform spells it: uppercase hexadecimal in RFC 4122 groups.
std::string GuidText(const engine::Guid& guid);

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_BINDING_H_

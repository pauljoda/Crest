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
#include "base/memory/raw_ptr_exclusion.h"
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
// The platform reaches the binding directly through a second table,
// crest_engine_pages_t: it asks a page's engine for view work with a
// PageRequest, answered at once, and hears what finishes later, such as a
// find's count or an export, as an EnginePresentation.
//
// Everything runs on Chromium's UI thread. The core delivers the commands a
// report causes before the report returns, and a command such as ClosePage
// must never destroy a WebContents inside one of its own observers, so no
// report is made on the stack of a Chromium callback: reports and
// presentations queue, and one task posted to the UI thread sends them in
// order. A page's snapshot is sent last in the turn in which it changed.
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
    // Moves `page`'s WebContents into the Browser of `window`. TRANSITIONAL
    // until the Browsers move into the binding.
    virtual bool MoveToWindow(const std::string& page, const std::string& window) = 0;
    // `page`'s view came on screen or left it, which its media follows.
    // TRANSITIONAL until the media session moves.
    virtual void VisibilityChanged(const std::string& page, bool visible) = 0;
  };

  static EngineBinding& Get();

  EngineBinding(const EngineBinding&) = delete;
  EngineBinding& operator=(const EngineBinding&) = delete;

  // The function table the platform registers with the core, the engine
  // contract the binding was built against, which the core checks, and the
  // platform's direct path to the binding.
  crest_engine_binding_t Table();
  static const std::array<uint8_t, 32>& Fingerprint();
  crest_engine_pages_t Pages();

  void SetShell(Shell* shell);
  // The engine is shutting down: nothing more is reported, and every page is
  // let go of without a report.
  void Dispose();

  // What the platform asks of a page directly that no PageRequest carries
  // yet. TRANSITIONAL until engine-offered pages and link routing move
  // (WP C (l)).
  bool Adopt(const std::string& page, const std::string& token);
  bool Stage(const std::string& page, const std::string& token, const std::string& url);
  void Load(const std::string& page, const std::string& url);
  // What `page` shows changed in a way only the shell sees, such as its media
  // session.
  void StateChanged(const std::string& page);

  // For the binding's pages.
  void Report(engine::EngineEvent event);
  void Present(engine::EnginePresentation presentation);
  void ReportStateSoon(const std::string& page);
  void PageLost(const std::string& page);
  bool LoadStagedNavigation(const std::string& page, const std::string& token, const GURL& url);
  void DiscardStagedNavigation(const std::string& token);
  engine::PageMediaActivity MediaActivity(const std::string& page);

 private:
  friend class base::NoDestructor<EngineBinding>;

  EngineBinding();
  ~EngineBinding();

  // What the binding sends once the turn ends: a report to the core or a
  // presentation to the platform, encoded.
  struct Outgoing {
    bool to_core;
    std::vector<uint8_t> message;
  };

  static void CREST_CALL Attach(void* context, uint64_t app, uint64_t engine, crest_engine_report_t report);
  static void CREST_CALL Run(void* context, const uint8_t* command, size_t length);
  static crest_status_t CREST_CALL Request(void* context, const uint8_t* request, size_t length, crest_buffer_t* out);
  static void CREST_CALL Release(void* context, crest_buffer_t* buffer);
  static void CREST_CALL PresentTo(void* context, crest_engine_present_t present, void* ui);

  // Each request, handled where it lands.
  bool Handle(const engine::GoToHistoryOffset& request);
  bool Handle(const engine::ReloadPage& request);
  bool Handle(const engine::StopLoading& request);
  bool Handle(const engine::ZoomPage& request);
  bool Handle(const engine::FindInPage& request);
  bool Handle(const engine::CapturePage& request);
  bool Handle(const engine::ExportPage& request);
  engine::InteractionState Handle(const engine::SaveInteractionState& request);
  bool Handle(const engine::RestoreInteractionState& request);
  bool Handle(const engine::MovePageToWindow& request);
  bool Handle(const engine::ShowPage& request);
  bool Handle(const engine::HidePage& request);
  engine::PageIconImage Handle(const engine::PageIcon& request);
  bool Handle(const engine::OpenStandalonePage& request);
  bool Handle(const engine::CloseStandalonePage& request);

  void Perform(engine::EngineCommand command);
  std::vector<uint8_t> Answer(const engine::PageRequest& request);
  void Create(const engine::CreatePage& creation, bool standalone);
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
  crest_engine_present_t present_ = nullptr;
  // The platform's own, handed back with each presentation.
  RAW_PTR_EXCLUSION void* ui_ = nullptr;
  bool disposing_ = false;
  std::map<std::string, std::unique_ptr<EnginePage>> pages_;
  std::deque<Outgoing> queue_;
  std::vector<std::string> due_;
  bool flush_posted_ = false;
  bool flushing_ = false;
  base::WeakPtrFactory<EngineBinding> weak_factory_{this};
};

// A GUID as the platform spells it: uppercase hexadecimal in RFC 4122 groups.
std::string GuidText(const engine::Guid& guid);

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_BINDING_H_

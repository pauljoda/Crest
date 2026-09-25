#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_PAGE_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_PAGE_H_

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "components/find_in_page/find_result_observer.h"
#include "content/public/browser/web_contents_observer.h"

class GURL;

namespace crest {

class EngineBinding;
class PageDocuments;

// One page the core asked Chromium to create, from its CreatePage until the
// engine lets it go. It turns the WebContents' own callbacks into the core's
// engine events, as every binding does:
//
// - A navigation to a new document starts, commits, then finishes with the
//   title it settled on, or fails.
// - A move within the document, such as `history.pushState` or a fragment,
//   starts and commits when the address changes, and finishes once the page's
//   title settles (see `kTitleSettleInterval`). A move while a new document is
//   still loading belongs to that load, which finishes it.
// - An icon is reported when the engine finds one for the document, and again
//   when the page's theme changes the colour behind it.
// - What the page shows, its PageSnapshot, is reported once in any turn in
//   which it changed, and only when it differs from the last one reported.
//
// The core decides what each event records; this only decides when the
// engine's callbacks amount to one. Addresses are in Crest's namespace, where
// the engine's own `chrome://` pages are `crest://` pages.
//
// It also answers what the platform asks of the page directly: its history,
// reload, find, zoom, capture, export and whether it is on screen. A
// standalone page, one of the engine's own that Settings shows, answers those
// and reports nothing to the core.
class EnginePage final : public content::WebContentsObserver,
                         public favicon::FaviconDriverObserver,
                         public find_in_page::FindResultObserver {
 public:
  // Where the page stands on the engine.
  enum class Phase {
    // The binding is creating its WebContents.
    kCreating,
    // A WebContents the engine offered is becoming the page instead.
    kAdopting,
    // The page has its WebContents.
    kLive,
    // The engine lost the WebContents on its own.
    kGone,
  };

  // How long a page's title must hold after a move within its document
  // before the move finishes. Sites that route in script change the address
  // first and set the new page's title a moment later.
  static constexpr base::TimeDelta kTitleSettleInterval = base::Milliseconds(500);
  // The longest a move within the document waits for its title, counted from
  // the move, so a page whose title never stops changing still records.
  static constexpr base::TimeDelta kTitleSettleLimit = base::Seconds(2);

  EnginePage(EngineBinding& binding, const engine::CreatePage& creation, bool standalone = false);
  EnginePage(const EnginePage&) = delete;
  EnginePage& operator=(const EnginePage&) = delete;
  ~EnginePage() override;

  const engine::Guid& id() const { return id_; }
  // The page's identity as the platform spells it.
  const std::string& key() const { return key_; }
  const std::string& profile() const { return profile_; }
  bool is_private() const { return is_private_; }
  // One of the engine's own pages that Settings shows, which the core never
  // hears of.
  bool standalone() const { return standalone_; }
  const std::string& window() const { return window_; }
  Phase phase() const { return phase_; }
  void set_phase(Phase phase) { phase_ = phase; }

  // Starts following `contents`, which is now the page.
  void Start(content::WebContents* contents);
  // Stops following the page, which the binding is letting go of.
  void Stop();

  // The app asked the page to load `url`: the core's LoadPage, or the
  // platform's own load. The page shows it is heading there at once; a page
  // still being created loads it once it exists.
  void Load(const std::string& url);
  // Keeps a link navigation the platform staged for the page's first load,
  // which a load of the same address then runs. False once the page loads.
  bool Stage(const std::string& token, const std::string& url);
  // Restores navigation history saved by `SaveInteractionState` in place of a
  // load of `expected_url`; a page still being created restores once it
  // exists. False when the state does not restore this page.
  bool Restore(std::vector<uint8_t> state, const std::string& expected_url);
  // The page's navigation history, or nothing before its first commit.
  std::optional<std::vector<uint8_t>> SaveInteractionState();
  // Runs what the app asked for before the page existed: the restore, the
  // staged navigation or the load.
  void LoadPending();
  // The token of the navigation staged for the page, which a closing page
  // discards.
  std::optional<std::string> TakeStagedToken();

  // The icon the engine found for the page's document.
  std::optional<std::vector<uint8_t>> icon() const;

  // What the platform asks of the page directly. Each answers whether the
  // page took it; what finishes later is presented.
  bool GoToOffset(int offset);
  bool Reload(bool bypasses_cache);
  bool StopLoading();
  bool Zoom(double factor);
  bool Find(const std::string& query, bool backwards, bool case_sensitive);
  bool Capture(const engine::Guid& capture_id, const std::optional<engine::PageArea>& area, double width);
  bool Export(const engine::Guid& export_id, engine::PageExportFormat format, double width);
  bool Show();
  bool Hide();

  // What the page shows changed; it reports once this turn ends.
  void StateChanged();
  // Reports what the page shows, when it differs from the last report. The
  // binding calls it once the turn in which it changed ends.
  void ReportState();

 private:
  struct StagedNavigation {
    std::string token;
    std::string url;
  };
  struct FoundIcon {
    std::vector<uint8_t> png;
    std::string url;
  };

  // content::WebContentsObserver:
  void DidStartNavigation(content::NavigationHandle* navigation) override;
  void DidRedirectNavigation(content::NavigationHandle* navigation) override;
  void DidFinishNavigation(content::NavigationHandle* navigation) override;
  void DidStartLoading() override;
  void DidStopLoading() override;
  void TitleWasSet(content::NavigationEntry* entry) override;
  void DidChangeVisibleSecurityState() override;
  void DidChangeThemeColor() override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) override;
  void OnAudioStateChanged(bool audible) override;
  void MediaStartedPlaying(const MediaPlayerInfo& info, const content::MediaPlayerId& id) override;
  void MediaStoppedPlaying(const MediaPlayerInfo& info,
                           const content::MediaPlayerId& id,
                           content::WebContentsObserver::MediaStoppedReason reason) override;
  void WebContentsDestroyed() override;

  // favicon::FaviconDriverObserver:
  void OnFaviconUpdated(favicon::FaviconDriver* driver,
                        NotificationIconType type,
                        const GURL& icon_url,
                        bool icon_url_changed,
                        const gfx::Image& image) override;

  // find_in_page::FindResultObserver:
  void OnFindResultAvailable(content::WebContents* contents) override;
  void OnFindTabHelperDestroyed(find_in_page::FindTabHelper* helper) override;

  void ApplyZoom();
  void Present(engine::EnginePresentation presentation);

  // The engine's own callbacks, as navigation events.
  void Navigate(const std::string& url);
  bool RestoreNow(const std::vector<uint8_t>& state, const std::string& expected_url);
  void Started(const std::string& url);
  void Committed(const std::string& url);
  void Finished(const std::string& url);
  void Failed(engine::PageFailure failure);
  void Interrupted();
  void MovedWithinDocument(const std::string& url);
  void TitleChanged();
  void NoteTitle();
  void FinishIfLoaded();
  void Settle();
  void CancelSettling();
  void PublishIcon(const gfx::Image& image);
  void UpdateTheme();
  void ReportIcon();
  void Report(engine::EngineEvent event);
  engine::PageSnapshot Snapshot() const;
  std::string Title() const;
  engine::PageSecurity Security() const;
  // The engine is about to load the address a page was asked for and shows
  // its initial blank document meanwhile, which is nothing the page shows.
  bool ShowsInitialBlank(const GURL& url) const;

  const raw_ref<EngineBinding> binding_;
  const bool standalone_;
  const engine::Guid id_;
  const std::string key_;
  const std::string profile_;
  const bool is_private_;
  const std::string window_;
  Phase phase_ = Phase::kCreating;

  // What the app asked for before the page existed.
  std::optional<std::string> pending_load_;
  std::optional<StagedNavigation> staged_;
  std::optional<std::vector<uint8_t>> pending_state_;

  // Where a navigation that has not committed is heading.
  std::optional<std::string> pending_url_;
  // The document's address as last reported.
  std::optional<std::string> document_url_;
  // The navigation to a new document the engine is running, by its ID.
  std::optional<int64_t> loading_navigation_;
  // A new document committed and has not finished loading.
  bool awaits_finish_ = false;
  // The title last reported.
  std::string reported_title_;
  // The move within the document waiting for its title, and the latest
  // moment it may finish.
  std::optional<std::string> settling_url_;
  base::TimeTicks settle_deadline_;
  base::OneShotTimer settle_timer_;
  // The image the engine found for the document, and the colour the page's
  // theme puts behind it.
  std::optional<FoundIcon> icon_;
  std::optional<engine::TabIconAccent> accent_;
  // The page changed since its last snapshot, which is due when the turn ends.
  bool report_due_ = false;
  std::optional<engine::PageSnapshot> reported_;

  // The zoom the platform asked for, which a page still being created takes
  // once it exists.
  std::optional<double> zoom_;
  // The engine's find, and whether a find waits for its count.
  raw_ptr<find_in_page::FindTabHelper> find_helper_ = nullptr;
  bool find_pending_ = false;
  std::unique_ptr<PageDocuments> documents_;
  base::WeakPtrFactory<EnginePage> weak_factory_{this};
};

// An engine address in Crest's namespace, where `chrome://` is `crest://`.
std::string PresentedURL(const GURL& url);
// A Crest address as the engine loads it.
GURL EngineURL(const std::string& url);

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_PAGE_H_

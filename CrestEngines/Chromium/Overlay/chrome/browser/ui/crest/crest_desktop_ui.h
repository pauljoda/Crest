#ifndef CHROME_BROWSER_UI_CREST_CREST_DESKTOP_UI_H_
#define CHROME_BROWSER_UI_CREST_CREST_DESKTOP_UI_H_

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "chrome/browser/ui/crest/crest_core_library.h"
#include "chrome/browser/ui/crest/crest_desktop_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_observer.h"
#include "content/public/browser/web_ui_controller.h"
#include "content/public/browser/web_ui_message_handler.h"
#include "content/public/browser/webui_config.h"
#include "content/public/common/url_constants.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/views/view_tracker.h"

namespace net {
struct RedirectInfo;
}

namespace network {
class SimpleURLLoader;
namespace mojom {
class URLResponseHead;
}
}  // namespace network

class GURL;

namespace crest {

// Where Crest's desktop interface runs.
inline constexpr char kCrestDesktopHost[] = "crest-desktop";
inline constexpr char kCrestDesktopURL[] = "chrome://crest-desktop/";

class CrestDesktopUI;
class InterfaceMenu;

class CrestDesktopUIConfig : public content::DefaultWebUIConfig<CrestDesktopUI> {
 public:
  CrestDesktopUIConfig() : DefaultWebUIConfig(content::kChromeUIScheme, kCrestDesktopHost) {}
};

// Crest's interface: the files of its bundle, read from beside the engine so
// a change to the interface needs no new engine, and its bridge to the core.
// The interface embeds the window's pages itself, with surface embeds.
class CrestDesktopUI : public content::WebUIController {
 public:
  explicit CrestDesktopUI(content::WebUI* web_ui);
  CrestDesktopUI(const CrestDesktopUI&) = delete;
  CrestDesktopUI& operator=(const CrestDesktopUI&) = delete;
  ~CrestDesktopUI() override;

 private:
  WEB_UI_CONTROLLER_TYPE_DECL();
};

// The interface's bridge to the core and the engine. A call is
// chrome.send("crestCore", [id, op, ...arguments]); its answer arrives as
// crestCoreReply(id, status, bytes). What the core changes on its own, and
// what another window's intent changed, arrives as crestCoreChanges(status,
// bytes), and what the engine presents as crestEnginePresentation(bytes).
// Bytes are the contract wire format, base64 encoded; this side never reads
// them. The window's own state arrives as crestWindowState(state), a key
// bound to one of the interface's commands as crestShortcut(command), a page
// keeping the keys of a command that runs on a second press as
// crestPageKept(command) (empty once that is over), a request to close its
// window as crestCloseRequested(last, stack, pages), and the engine's notices
// as crestEngineNotice(message, kind) and crestUnavailable(feature). The
// interface's context menus run as Windows' own (the op "menu"), a page's
// certificate shows in the system's certificate dialog (the op "certificate"),
// and the filter lists the core asks for, and the search engine's
// suggestions, download as the Mac app downloads them (the op "fetchText",
// whose last argument says which: "filterList" or "searchSuggestions"). A
// precision touchpad's scroll over the interface arrives with the phases the
// system gave it, which the page's wheel events leave out, as
// crestWheel(phase, momentumPhase, deltaX, deltaY, x, y, seconds): the
// phases are blink::WebMouseWheelEvent's flags, the deltas follow the DOM's
// wheel event, and the place and deltas are in CSS pixels. An extension's
// button runs its action for a page, opening the extension's popup beside the
// button as Chrome opens it from its toolbar (the op "runExtension"). A
// locked Space asks Windows Hello whether the device's owner is there, over
// the window that asks (the op "verifyOwner"), as the Mac asks
// LocalAuthentication.
class DesktopBridge : public content::WebUIMessageHandler,
                      public content::RenderWidgetHost::InputEventObserver,
                      public content::RenderWidgetHostObserver {
 public:
  DesktopBridge();
  DesktopBridge(const DesktopBridge&) = delete;
  DesktopBridge& operator=(const DesktopBridge&) = delete;
  ~DesktopBridge() override;

  // The window this interface shows: its frame's, or before the frame is
  // known, the one its address names.
  std::string Window();
  // The keys this window's interface binds to its commands now.
  const std::vector<Shortcut>& shortcuts() const { return shortcuts_; }

  void Changes(const CoreReply& batch);
  void Presentation(const std::vector<uint8_t>& presentation);
  void Unavailable(int feature);
  void Notice(const std::string& message, const std::string& kind);
  void WindowState(const base::DictValue& state);
  void RunCommand(const std::string& command);
  void PageKept(const std::string& command);
  // The window was asked to close; `stack` is the windows' identities, front
  // first, and `pages` the pages it shows. The interface answers with the
  // window op "close".
  void CloseRequested(bool last, base::ListValue stack, base::ListValue pages);

  // content::WebUIMessageHandler:
  using content::WebUIMessageHandler::IsJavascriptAllowed;
  void RegisterMessages() override;
  void OnJavascriptAllowed() override;
  void OnJavascriptDisallowed() override;

  // content::RenderWidgetHost::InputEventObserver:
  void OnInputEvent(const content::RenderWidgetHost& host,
                    const blink::WebInputEvent& event,
                    InputEventSource source) override;

  // content::RenderWidgetHostObserver:
  void RenderWidgetHostDestroyed(content::RenderWidgetHost* host) override;

 private:
  void OnCall(const base::ListValue& arguments);
  CoreReply Answer(const std::string& op, const base::ListValue& arguments);
  void Reply(const base::Value& id, const CoreReply& reply);
  // Where the file of the download the core asks about goes, answered later
  // as {"path": …} (null when the person cancels or no folder takes it), or
  // {"taken": true} when another window already answers it.
  void ResolveDownloadDestination(base::Value id, const std::string& prompt, const std::string& suggested,
                                  bool asks);
  void AnswerDownloadDestination(base::Value id, base::FilePath path);
  // Runs the menu `items` describe at `x`, `y` in the interface, as Windows'
  // own context menus run, answered later as the chosen item's id or null.
  void ShowMenu(base::Value id, const std::string& items, double x, double y);
  void AnswerMenu(base::Value id, std::optional<std::string> chosen);
  // Asks Windows Hello, over this window, to verify the device's owner for
  // `reason`, answered later as {"result"}: "verified", "canceled" (the person
  // dismissed it or ran out of tries), "busy" (another verification is up),
  // or "unavailable" (no Windows Hello, or it is not set up or allowed).
  void VerifyOwner(base::Value id, const std::string& reason);
  void AnswerOwner(base::Value id, std::string_view result);
  // Fetches `address`, an https address, as text: without cookies or stored
  // credentials, through no cache, following redirects only to other https
  // addresses, sending the validators of a copy the interface already holds,
  // and giving up past the longest list the core keeps. `purpose` names what
  // it is for, a filter list or the search engine's suggestions for what the
  // person typed, which the network's request policy tells apart. It is
  // answered later as {"status", "text", "entityTag", "lastModified",
  // "tooLarge"}: status 0 when no response arrived, and text null unless a
  // 2xx response brought UTF-8.
  void FetchText(base::Value id,
                 const std::string& address,
                 const std::string& entity_tag,
                 const std::string& last_modified,
                 const std::string& purpose);
  void FetchRedirected(int fetch,
                       const GURL& url_before_redirect,
                       const net::RedirectInfo& redirect,
                       const network::mojom::URLResponseHead& head,
                       std::vector<std::string>* removed_headers);
  void FetchDownloaded(int fetch, base::FilePath file);
  void AnswerFetch(int fetch, std::optional<std::string> text);
  // Runs the action of the extension `extension_id` for the page `page_id`,
  // as a click on its button in Chrome's toolbar does, and opens its popup
  // beside `anchor`, the button's place in the interface in CSS pixels.
  // Answers {"ran", "popup", "panel"}: whether the action ran, and whether it
  // opened its popup or asked for its side panel.
  CoreReply RunExtension(const std::string& extension_id, const std::string& page_id, const gfx::Rect& anchor);
  // An invisible view at `rect` in the interface, which an extension's popup
  // points at.
  views::View* PopupAnchor(const gfx::Rect& rect);

  // One fetch under way: the call it answers and its loader.
  struct Fetch {
    Fetch();
    Fetch(Fetch&&);
    Fetch& operator=(Fetch&&);
    ~Fetch();
    base::Value id;
    std::unique_ptr<network::SimpleURLLoader> loader;
  };

  std::vector<Shortcut> shortcuts_;
  // The menu running now, or null.
  std::unique_ptr<InterfaceMenu> menu_;
  // Hears the interface's own widget, whose touchpad phases go to the
  // interface, or stops hearing it.
  void ObserveWidget(content::RenderWidgetHost* host);

  // Where the last extension popup points, in the interface's view.
  views::ViewTracker popup_anchor_;
  // The interface's widget whose input this bridge hears, or null.
  raw_ptr<content::RenderWidgetHost> observed_widget_ = nullptr;
  // The fetches under way, by the number each was given.
  std::map<int, Fetch> fetches_;
  int next_fetch_ = 0;
  base::WeakPtrFactory<DesktopBridge> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_DESKTOP_UI_H_

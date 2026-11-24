#ifndef CHROME_BROWSER_UI_CREST_CREST_DESKTOP_HOST_H_
#define CHROME_BROWSER_UI_CREST_CREST_DESKTOP_HOST_H_

#include <atomic>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/string_util.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "chrome/browser/ui/crest/crest_core_library.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"

class Browser;
class Profile;

namespace content {
class WebContents;
}

namespace input {
struct NativeWebKeyboardEvent;
}

namespace views {
class Widget;
}

namespace crest {

class DesktopBridge;
class DesktopFrame;

// Whether this is Crest as Setup installs it: chrome.exe in Chromium's
// layout for Crest's install mode, <...>\Crest\Application\chrome.exe, with
// the core and the interface beside it. The installed product is Crest with
// no switches at all, keeps its profiles in Chromium's own folder for the
// install mode, and updates itself; a development engine is Crest only when
// launched with --crest-control-plane and a profile folder of its own.
bool IsInstalledProduct();

// What Chromium offers that Crest's desktop interface answers with a notice
// instead, as the Mac's CrestUnavailableFeature does.
enum class UnavailableFeature {
  kAutofill,
  kPaymentAutofill,
  kAddressAutofill,
  kAutofillAI,
  kProfiles,
  kEyeDropper,
  kCaretBrowsing,
  kPrivateBrowsing,
  kChromeLabs,
  kTranslation,
};

// A key a window's interface binds to one of its commands, `command`: the
// key's virtual-key code, as Chromium's own accelerators match keys, with
// exactly these modifiers held, and who answers it while a focused page or
// field uses it too, as the core's shortcut preference says.
struct Shortcut {
  std::string command;
  int key_code = 0;
  bool control = false;
  bool shift = false;
  bool alt = false;
  // The command runs before a focused page sees the key.
  bool before_page = false;
  // A quick second press of keys a page kept runs the command.
  bool second_press = false;
  // The keys edit text, so a focused page or field sees them first and the
  // command runs only when it lets them go.
  bool yields_to_text = false;
};

// Where a key down is when the shell is offered it: about to reach the
// interface's own views, about to reach a page, or let go by either.
enum class KeyStage {
  kBeforeInterface,
  kBeforePage,
  kLetGo,
};

// Crest's shell on the platforms whose interface Chromium draws (Windows,
// and Linux next). It owns the core app, opens the Crest windows, each a
// widget whose whole client area is Crest's interface, and answers the
// binding's Shell: the engine's pages are embedded into the interface, which
// places, clips and animates them, so the shell hosts no views of its own
// beside a page. Everything runs on Chromium's UI thread.
class DesktopHost : public EngineBinding::Shell {
 public:
  static DesktopHost& Get();

  DesktopHost(const DesktopHost&) = delete;
  DesktopHost& operator=(const DesktopHost&) = delete;

  bool started() const { return started_; }
  // Loads the core, hands the binding this shell and opens the first window.
  // `bootstrap` is the Browser startup made, in the engine's startup profile,
  // which no Space owns and the interface's own pages run in.
  void Start(Browser* bootstrap);

  // A Crest window showing the interface: the saved window `window` names, or
  // a new one. It comes in front of the others when `activates`. A launch's
  // first window `launches` until the core names the saved window it is.
  DesktopFrame* OpenWindow(std::optional<std::string> window = std::nullopt,
                           bool activates = true,
                           bool launches = false);
  // The window `window` names, or nullptr.
  DesktopFrame* FrameFor(const std::string& window) const;
  // The window whose interface `contents` are, or nullptr.
  DesktopFrame* FrameForContents(const content::WebContents* contents) const;
  // The window in use: the one most recently active, else the first opened.
  DesktopFrame* FrameInUse() const;
  // The Crest window `browser`'s pages show in, or nullptr.
  DesktopFrame* FrameForBrowser(const Browser* browser) const;
  // The widget of that window, or nullptr.
  views::Widget* WidgetForBrowser(const Browser* browser) const;
  void FrameClosed(DesktopFrame* frame);
  // Asks `frame`'s interface to close its window, telling it whether it is
  // the last one and how the windows stack, front first. Answers false when
  // no interface can be asked.
  bool RequestClose(DesktopFrame* frame);
  // Tells `frame`'s interface what its window buttons now draw from.
  void FrameStateChanged(DesktopFrame* frame, const base::DictValue& state);
  // Brings `frame` in front of the others, restored, as a launch does.
  void BringForward(DesktopFrame* frame);
  // Quits Crest as closing its last window does: every window's interface
  // hears it is closing with the others, so each remembers every window for
  // the next launch rather than closing its own for good.
  void Quit();

  // A launch's links and documents, as Chromium read them from its command
  // line. Before the first window is open they wait for its interface; a
  // launch handed to the running Crest brings the window in use forward and
  // hands them to it. Answers whether the launch needs nothing more, which a
  // launch handed to the running Crest never does.
  bool OpenLaunch(std::vector<std::string> urls);
  // Takes the links and documents launches brought before `bridge`'s window
  // could open them, as {"urls", "stack"}, the windows front first. From then
  // on that window hears the next ones while it is the window in use.
  base::DictValue TakeLaunchOpens(DesktopBridge* bridge);

  // Offers `event`, a key pressed in `frame`'s window, to the commands its
  // interface binds, at `stage`, and answers whether one ran and took it.
  // Before a page, the command's preference decides, as on the Mac: Prefer
  // Crest runs it now, Use Both runs it on a quick second press of keys the
  // page kept, and otherwise the page sees the key and the command runs when
  // the page lets it go. The interface's own views get every command's keys
  // first but those that edit text. `receiver` names what the key went to,
  // so a press that reaches another page is that page's first.
  bool OfferKey(DesktopFrame* frame,
                const input::NativeWebKeyboardEvent& event,
                KeyStage stage,
                const void* receiver);
  // The same for a key pressed on one of `browser`'s pages.
  bool OfferKey(const Browser* browser, const input::NativeWebKeyboardEvent& event, KeyStage stage);

  // Where the interface's files are and the profile its pages run in.
  const base::FilePath& interface_directory() const { return interface_directory_; }
  Profile* interface_profile() const { return interface_profile_; }

  // The interfaces that hear what the core and the engine publish.
  void AddBridge(DesktopBridge* bridge);
  void RemoveBridge(DesktopBridge* bridge);

  // What an interface asks of the core, on the contract wire. A creation the
  // first interface asks for makes the app every window shares; a later one
  // joins it. What an intent changed reaches every other interface too.
  CoreReply Create(const std::vector<uint8_t>& fingerprint, const std::vector<uint8_t>& configuration);
  CoreReply Dispatch(DesktopBridge* sender, const std::vector<uint8_t>& intent);
  CoreReply Query(const std::vector<uint8_t>& query);
  // Registers Chromium's binding with the app, once, with the registration
  // the interface encoded.
  CoreReply RegisterEngine(const std::vector<uint8_t>& fingerprint, const std::vector<uint8_t>& registration);
  // A page request, answered by the page's binding at once.
  CoreReply Request(const std::vector<uint8_t>& request);
  // The surface embed identity of `page`'s contents, which the interface's
  // <embed> names, or empty when the engine has no contents for it.
  std::string EmbedPage(const std::string& page);

  // Claims the core's question about a download's destination for the window
  // that asks first; false when another window already answers it.
  bool ClaimDownloadPrompt(const std::string& prompt) {
    return claimed_download_prompts_.insert(base::ToLowerASCII(prompt)).second;
  }

  // Chromium asked for something Crest does not offer here; the window in use
  // says so.
  void ShowUnavailable(UnavailableFeature feature);
  // A notice in the window in use, of `kind` "link" or "confirmation", as
  // Chromium's toasts are on the Mac.
  void ShowNotice(const std::string& message, const std::string& kind);

  // EngineBinding::Shell:
  std::optional<EngineBinding::WindowPlacement> ReserveWindow(const std::string& profile, bool own_window) override;
  void PresentWindow(const EngineBinding::WindowPlacement& placement, bool focused) override;
  void ReleasePage(const std::string& page) override;
  void DockInspector(const std::string& page, content::WebContents* frontend) override;
  void ReleaseProfile(const std::string& profile) override;
  void RetractSidePanels(Profile* profile, const std::string& extension, std::optional<int> tab) override;

 private:
  friend class base::NoDestructor<DesktopHost>;

  DesktopHost();
  ~DesktopHost() override;

  // The core published changes of its own: drained on the UI thread's next
  // turn and sent to every interface.
  static void CREST_CALL Wake(void* context);
  void DrainSoon();
  void Drain();
  static void CREST_CALL Present(void* ui, const uint8_t* presentation, size_t length);
  // Sends a batch of changes to every interface but `except`.
  void Publish(const CoreReply& batch, DesktopBridge* except);
  // The interface showing `frame`'s window, or nullptr before it loads.
  DesktopBridge* BridgeFor(const DesktopFrame* frame) const;
  // The command `bridge`'s window binds `event`'s keys to, or nullptr.
  static const Shortcut* ShortcutFor(const DesktopBridge& bridge, const input::NativeWebKeyboardEvent& event);

  // A press of a Use Both command's keys that a focused page saw first: the
  // command, the event's own time, what it went to and the window it was
  // pressed in. Chromium hands a press the page lets go back as the same
  // event, and a press the page keeps never comes back.
  struct KeptPress {
    std::string command;
    base::TimeTicks timestamp;
    // Only compared, never followed.
    uintptr_t receiver = 0;
    std::string window;
  };
  // Whether `event` runs `shortcut`'s command before the page sees it.
  bool RunsBeforePage(DesktopBridge& bridge,
                      const Shortcut& shortcut,
                      const input::NativeWebKeyboardEvent& event,
                      const void* receiver);
  // Whether a press a page let go is one whose second press already ran its
  // command; any other press it let go is no longer kept.
  bool PageLetGo(const input::NativeWebKeyboardEvent& event);
  // Shows the kept press's window how to run its command instead.
  void ShowKeptHint();
  // Forgets the kept press, and puts away the hint it showed.
  void ForgetKeptPress();
  // The windows' identities, front first.
  base::ListValue WindowStack() const;
  // Hands the launches' links and documents to the window in use once its
  // interface takes them.
  void DeliverLaunchOpens();

  bool started_ = false;
  base::FilePath interface_directory_;
  raw_ptr<Profile> interface_profile_ = nullptr;
  std::unique_ptr<CoreLibrary> core_;
  uint64_t app_ = 0;
  uint64_t engine_ = 0;
  std::atomic<bool> drain_posted_{false};
  std::vector<std::unique_ptr<DesktopFrame>> frames_;
  std::set<raw_ptr<DesktopBridge>> bridges_;
  std::optional<KeptPress> kept_press_;
  // A kept press whose second press already ran its command, should the page
  // let it go after all.
  std::optional<base::TimeTicks> answered_press_;
  // The window showing the kept press's hint, or empty.
  std::string hint_window_;
  base::OneShotTimer hint_timer_;
  std::set<std::string> claimed_download_prompts_;
  // Links and documents launches brought that no window has opened yet.
  std::vector<std::string> launch_opens_;
  // The interfaces that took the launches' opens, which hear the next ones.
  std::set<raw_ptr<DesktopBridge>> open_receivers_;
  // Every window is closing with the others.
  bool quitting_ = false;
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_DESKTOP_HOST_H_

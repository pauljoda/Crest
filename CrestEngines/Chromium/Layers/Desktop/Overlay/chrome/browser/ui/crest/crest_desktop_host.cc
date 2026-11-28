#include "chrome/browser/ui/crest/crest_desktop_host.h"

#include <algorithm>
#include <functional>
#include <utility>

#include "base/auto_reset.h"
#include "base/base_paths.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/path_service.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/uuid.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/crest/crest_desktop_frame.h"
#include "chrome/browser/ui/crest/crest_desktop_ui.h"
#include "chrome/browser/ui/crest/crest_engine_browsers.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "chrome/browser/ui/crest/crest_permission_prompt.h"
#include "chrome/browser/ui/startup/startup_tab.h"
#include "chrome/browser/ui/startup/startup_tab_provider.h"
#include "chrome/browser/ui/toasts/api/toast_id.h"
#include "chrome/install_static/install_modes.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/surface_embed/browser/surface_embed_handle.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/webui_config_map.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "ui/views/widget/widget.h"

namespace crest {

namespace {

// The switch that hosts Crest, and the ones that place its parts in development.
constexpr char kHostSwitch[] = "crest-control-plane";
constexpr char kCoreSwitch[] = "crest-core";
constexpr char kInterfaceSwitch[] = "crest-interface";

base::FilePath BesideExecutable(const base::FilePath::StringType& name) {
  return base::PathService::CheckedGet(base::DIR_EXE).Append(name);
}

base::FilePath SwitchOr(const char* name, const base::FilePath& fallback) {
  const auto* command_line = base::CommandLine::ForCurrentProcess();
  return command_line->HasSwitch(name) ? command_line->GetSwitchValuePath(name) : fallback;
}

}  // namespace

// static
DesktopHost& DesktopHost::Get() {
  static base::NoDestructor<DesktopHost> host;
  return *host;
}

DesktopHost::DesktopHost() = default;
DesktopHost::~DesktopHost() = default;

void DesktopHost::Start(Browser* bootstrap) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (started_) return;
  started_ = true;
  interface_profile_ = bootstrap->GetProfile();
  // The interface's files are served only from inside this folder, which a
  // relative switch would leave ambiguous.
  interface_directory_ =
      base::MakeAbsoluteFilePath(SwitchOr(kInterfaceSwitch, BesideExecutable(FILE_PATH_LITERAL("interface"))));
  core_ = CoreLibrary::Load(SwitchOr(kCoreSwitch, BesideExecutable(FILE_PATH_LITERAL("CrestCore.Native.dll"))));
  CHECK(core_) << "Crest cannot run without its native core";
  content::WebUIConfigMap::GetInstance().AddWebUIConfig(std::make_unique<CrestDesktopUIConfig>());
  auto& binding = EngineBinding::Get();
  binding.SetShell(this);
  crest_engine_pages_t pages = binding.Pages();
  pages.present_to(pages.context, &DesktopHost::Present, this);
  OpenWindow(std::nullopt, /*activates=*/true, /*launches=*/true);
}

DesktopFrame* DesktopHost::OpenWindow(std::optional<std::string> window, bool activates, bool launches) {
  std::string name = base::ToUpperASCII(window ? *window : base::Uuid::GenerateRandomV4().AsLowercaseString());
  frames_.push_back(std::make_unique<DesktopFrame>(std::move(name), interface_profile_.get(), launches));
  DesktopFrame* frame = frames_.back().get();
  frame->Show(activates);
  return frame;
}

DesktopFrame* DesktopHost::FrameForContents(const content::WebContents* contents) const {
  for (const auto& frame : frames_) {
    if (frame->interface_contents() == contents) return frame.get();
  }
  return nullptr;
}

DesktopFrame* DesktopHost::FrameFor(const std::string& window) const {
  for (const auto& frame : frames_) {
    if (base::EqualsCaseInsensitiveASCII(frame->window(), window)) return frame.get();
  }
  return nullptr;
}

DesktopFrame* DesktopHost::FrameInUse() const {
  DesktopFrame* latest = nullptr;
  for (const auto& frame : frames_) {
    if (!latest || frame->activation() > latest->activation()) latest = frame.get();
  }
  return latest;
}

DesktopFrame* DesktopHost::FrameForBrowser(const Browser* browser) const {
  if (!started_) return nullptr;
  const auto& browsers = EngineBinding::Get().Browsers();
  DesktopFrame* frame = FrameFor(browsers.WindowOf(browser));
  if (!frame) frame = FrameFor(browsers.creating_window());
  if (!frame) frame = FrameInUse();
  return frame;
}

views::Widget* DesktopHost::WidgetForBrowser(const Browser* browser) const {
  DesktopFrame* frame = FrameForBrowser(browser);
  return frame ? frame->widget() : nullptr;
}

void DesktopHost::FrameClosed(DesktopFrame* frame) {
  EngineBinding::Get().Browsers().CloseWindow(frame->window());
  std::erase_if(frames_, [frame](const auto& kept) { return kept.get() == frame; });
}

base::ListValue DesktopHost::WindowStack() const {
  std::vector<DesktopFrame*> stacked;
  for (const auto& open : frames_) stacked.push_back(open.get());
  std::ranges::sort(stacked, std::ranges::greater(), &DesktopFrame::activation);
  base::ListValue stack;
  for (DesktopFrame* open : stacked) stack.Append(open->window());
  return stack;
}

bool DesktopHost::RequestClose(DesktopFrame* frame) {
  DesktopBridge* bridge = BridgeFor(frame);
  if (!bridge || !bridge->IsJavascriptAllowed()) return false;
  base::ListValue stack = WindowStack();
  // The window's pages, which the interface lets go before the window goes,
  // as the Mac's do: a page the engine closed by itself would close its tab.
  auto& binding = EngineBinding::Get();
  base::ListValue pages;
  for (EnginePage* page : binding.LivePages()) {
    Browser* browser = binding.Browsers().Holding(page->web_contents());
    if (browser && base::EqualsCaseInsensitiveASCII(binding.Browsers().WindowOf(browser), frame->window())) {
      pages.Append(page->key());
    }
  }
  // While Crest quits, every window closes as the last one does, so the next
  // launch reopens them all.
  bridge->CloseRequested(frames_.size() == 1 || quitting_, std::move(stack), std::move(pages));
  return true;
}

void DesktopHost::FrameStateChanged(DesktopFrame* frame, const base::DictValue& state) {
  if (DesktopBridge* bridge = BridgeFor(frame)) bridge->WindowState(state);
}

void DesktopHost::BringForward(DesktopFrame* frame) {
  views::Widget* widget = frame->widget();
  if (widget->IsMinimized()) widget->Restore();
  widget->Show();
  widget->Activate();
}

void DesktopHost::Quit() {
  if (quitting_) return;
  quitting_ = true;
  std::vector<views::Widget*> widgets;
  for (const auto& frame : frames_) widgets.push_back(frame->widget());
  // Each window asks its interface first, as its own close button does.
  for (views::Widget* widget : widgets) widget->Close();
}

bool DesktopHost::OpenLaunch(std::vector<std::string> urls) {
  if (!started_) {
    // The first launch: the window it is about to open takes them.
    launch_opens_.insert(launch_opens_.end(), urls.begin(), urls.end());
    return false;
  }
  // Launching Crest again while it runs brings it forward, as Windows
  // browsers come forward. The window Crest is about to close has nothing
  // to bring.
  DesktopFrame* frame = FrameInUse();
  if (!frame || quitting_) return true;
  BringForward(frame);
  launch_opens_.insert(launch_opens_.end(), urls.begin(), urls.end());
  DeliverLaunchOpens();
  return true;
}

base::DictValue DesktopHost::TakeLaunchOpens(DesktopBridge* bridge) {
  open_receivers_.insert(bridge);
  base::ListValue urls;
  for (std::string& url : launch_opens_) urls.Append(std::move(url));
  launch_opens_.clear();
  return base::DictValue().Set("urls", std::move(urls)).Set("stack", WindowStack());
}

void DesktopHost::DeliverLaunchOpens() {
  DesktopFrame* frame = FrameInUse();
  DesktopBridge* bridge = frame ? BridgeFor(frame) : nullptr;
  // A window whose interface hasn't taken a launch's opens yet still boots;
  // it takes these with them.
  if (launch_opens_.empty() || !bridge || !open_receivers_.contains(bridge) || !bridge->IsJavascriptAllowed()) return;
  base::DictValue opens = TakeLaunchOpens(bridge);
  bridge->OpenExternal(std::move(*opens.FindList("urls")), std::move(*opens.FindList("stack")));
}

bool DesktopHost::OfferKey(DesktopFrame* frame,
                           const input::NativeWebKeyboardEvent& event,
                           KeyStage stage,
                           const void* receiver) {
  // A command runs once, on the key going down.
  if (event.GetType() != input::NativeWebKeyboardEvent::Type::kRawKeyDown) return false;
  if (stage == KeyStage::kLetGo && PageLetGo(event)) return true;
  DesktopBridge* bridge = frame ? BridgeFor(frame) : nullptr;
  const Shortcut* shortcut = bridge ? ShortcutFor(*bridge, event) : nullptr;
  if (!shortcut) return false;
  switch (stage) {
    case KeyStage::kBeforeInterface:
      if (shortcut->yields_to_text) return false;
      break;
    case KeyStage::kBeforePage:
      if (shortcut->yields_to_text || !RunsBeforePage(*bridge, *shortcut, event, receiver)) return false;
      break;
    case KeyStage::kLetGo:
      break;
  }
  bridge->RunCommand(shortcut->command);
  return true;
}

bool DesktopHost::OfferKey(const Browser* browser, const input::NativeWebKeyboardEvent& event, KeyStage stage) {
  // A key comes from the window in use, which may show a page another
  // window opened, as windows over one Space share its pages.
  return OfferKey(started_ ? FrameInUse() : nullptr, event, stage, browser);
}

bool DesktopHost::RunsBeforePage(DesktopBridge& bridge,
                                 const Shortcut& shortcut,
                                 const input::NativeWebKeyboardEvent& event,
                                 const void* receiver) {
  // How long a press waits for the page to let it go before the window shows
  // how to run the command, and how long after it a second press still runs
  // the command, as on the Mac.
  constexpr base::TimeDelta kHintDelay = base::Milliseconds(250);
  constexpr base::TimeDelta kSecondPressWindow = base::Seconds(2);
  if (shortcut.before_page) return true;
  if (!shortcut.second_press || (event.GetModifiers() & blink::WebInputEvent::kIsAutoRepeat)) return false;
  const base::TimeTicks timestamp = event.TimeStamp();
  const uintptr_t to = reinterpret_cast<uintptr_t>(receiver);
  if (kept_press_ && kept_press_->timestamp != timestamp && kept_press_->command == shortcut.command &&
      kept_press_->receiver == to && timestamp - kept_press_->timestamp <= kSecondPressWindow) {
    answered_press_ = kept_press_->timestamp;
    ForgetKeptPress();
    return true;
  }
  if (kept_press_ && kept_press_->timestamp == timestamp) return false;
  ForgetKeptPress();
  kept_press_ = KeptPress{shortcut.command, timestamp, to, bridge.Window()};
  hint_timer_.Start(FROM_HERE, kHintDelay, base::BindOnce(&DesktopHost::ShowKeptHint, base::Unretained(this)));
  return false;
}

bool DesktopHost::PageLetGo(const input::NativeWebKeyboardEvent& event) {
  if (answered_press_ == event.TimeStamp()) {
    answered_press_.reset();
    return true;
  }
  if (kept_press_ && kept_press_->timestamp == event.TimeStamp()) ForgetKeptPress();
  return false;
}

void DesktopHost::ShowKeptHint() {
  if (!kept_press_) return;
  DesktopFrame* frame = FrameFor(kept_press_->window);
  DesktopBridge* bridge = frame ? BridgeFor(frame) : nullptr;
  if (!bridge) return;
  hint_window_ = kept_press_->window;
  bridge->PageKept(kept_press_->command);
}

void DesktopHost::ForgetKeptPress() {
  kept_press_.reset();
  hint_timer_.Stop();
  if (hint_window_.empty()) return;
  DesktopFrame* frame = FrameFor(hint_window_);
  hint_window_.clear();
  if (DesktopBridge* bridge = frame ? BridgeFor(frame) : nullptr) bridge->PageKept(std::string());
}

DesktopBridge* DesktopHost::BridgeFor(const DesktopFrame* frame) const {
  for (DesktopBridge* bridge : bridges_) {
    if (base::EqualsCaseInsensitiveASCII(bridge->Window(), frame->window())) return bridge;
  }
  return nullptr;
}

// static
const Shortcut* DesktopHost::ShortcutFor(const DesktopBridge& bridge, const input::NativeWebKeyboardEvent& event) {
  // The system's own modifier (the Windows key) is never Crest's, and AltGr
  // types characters.
  const int modifiers = event.GetModifiers();
  if (modifiers & (blink::WebInputEvent::kMetaKey | blink::WebInputEvent::kAltGrKey)) return nullptr;
  const bool control = modifiers & blink::WebInputEvent::kControlKey;
  const bool shift = modifiers & blink::WebInputEvent::kShiftKey;
  const bool alt = modifiers & blink::WebInputEvent::kAltKey;
  for (const Shortcut& shortcut : bridge.shortcuts()) {
    if (shortcut.key_code == event.windows_key_code && shortcut.control == control && shortcut.shift == shift &&
        shortcut.alt == alt) {
      return &shortcut;
    }
  }
  return nullptr;
}

void DesktopHost::AddBridge(DesktopBridge* bridge) {
  bridges_.insert(bridge);
}

void DesktopHost::RemoveBridge(DesktopBridge* bridge) {
  bridges_.erase(bridge);
  open_receivers_.erase(bridge);
  ReleaseDownloadPrompts(bridge);
}

CoreReply DesktopHost::Create(const std::vector<uint8_t>& fingerprint, const std::vector<uint8_t>& configuration) {
  if (app_) return {CREST_OK, {}};
  CoreReply reply = core_->Create(fingerprint, configuration, &app_);
  if (reply.status == CREST_OK) core_->SetWake(app_, &DesktopHost::Wake, this);
  return reply;
}

CoreReply DesktopHost::Dispatch(DesktopBridge* sender, const std::vector<uint8_t>& intent) {
  if (!app_) return {CREST_INVALID_HANDLE, {}};
  CoreReply reply = core_->Dispatch(app_, intent);
  if (reply.status == CREST_OK) Publish(reply, sender);
  return reply;
}

CoreReply DesktopHost::Query(const std::vector<uint8_t>& query) {
  if (!app_) return {CREST_INVALID_HANDLE, {}};
  return core_->Query(app_, query);
}

CoreReply DesktopHost::RegisterEngine(const std::vector<uint8_t>& fingerprint,
                                      const std::vector<uint8_t>& registration) {
  if (!app_) return {CREST_INVALID_HANDLE, {}};
  if (engine_) return {CREST_OK, {}};
  const crest_engine_binding_t table = EngineBinding::Get().Table();
  return core_->RegisterEngine(app_, fingerprint, registration, table, &engine_);
}

CoreReply DesktopHost::Request(const std::vector<uint8_t>& request) {
  crest_engine_pages_t pages = EngineBinding::Get().Pages();
  crest_buffer_t answer{};
  CoreReply reply;
  reply.status = pages.request(pages.context, request.data(), request.size(), &answer);
  if (answer.bytes && answer.length) reply.bytes.assign(answer.bytes, answer.bytes + answer.length);
  if (answer.bytes) pages.release(pages.context, &answer);
  return reply;
}

std::string DesktopHost::EmbedPage(const std::string& page) {
  EnginePage* engine_page = EngineBinding::Get().Find(base::ToUpperASCII(page));
  content::WebContents* contents = engine_page ? engine_page->web_contents() : nullptr;
  if (!contents) return {};
  auto* handle = surface_embed::SurfaceEmbedHandle::FromWebContents(contents);
  if (!handle) {
    surface_embed::SurfaceEmbedHandle::CreateForWebContents(contents);
    handle = surface_embed::SurfaceEmbedHandle::FromWebContents(contents);
  }
  return handle->id().ToString();
}

void DesktopHost::ShowUnavailable(UnavailableFeature feature) {
  DesktopFrame* frame = FrameInUse();
  if (DesktopBridge* bridge = frame ? BridgeFor(frame) : nullptr) bridge->Unavailable(static_cast<int>(feature));
}

void DesktopHost::ShowNotice(const std::string& message, const std::string& kind) {
  DesktopFrame* frame = FrameInUse();
  if (DesktopBridge* bridge = frame ? BridgeFor(frame) : nullptr) bridge->Notice(message, kind);
}

// static
void CREST_CALL DesktopHost::Wake(void* context) {
  static_cast<DesktopHost*>(context)->DrainSoon();
}

void DesktopHost::DrainSoon() {
  if (drain_posted_.exchange(true)) return;
  content::GetUIThreadTaskRunner({})->PostTask(
      FROM_HERE, base::BindOnce(&DesktopHost::Drain, base::Unretained(this)));
}

void DesktopHost::Drain() {
  drain_posted_ = false;
  if (!app_) return;
  CoreReply batch = core_->Drain(app_);
  if (batch.status == CREST_OK) Publish(batch, nullptr);
  core_->EndTurn(app_);
}

// static
void CREST_CALL DesktopHost::Present(void* ui, const uint8_t* presentation, size_t length) {
  auto* host = static_cast<DesktopHost*>(ui);
  const std::vector<uint8_t> bytes(presentation, presentation + length);
  for (DesktopBridge* bridge : host->bridges_) bridge->Presentation(bytes);
}

void DesktopHost::Publish(const CoreReply& batch, DesktopBridge* except) {
  for (DesktopBridge* bridge : bridges_) {
    if (bridge != except) bridge->Changes(batch);
  }
}

std::optional<EngineBinding::WindowPlacement> DesktopHost::ReserveWindow(const std::string& profile,
                                                                         bool own_window) {
  // Crest is one window: an engine Browser joins the window in use, in the
  // Space the core decides when its first tab is offered.
  DesktopFrame* frame = own_window ? OpenWindow() : FrameInUse();
  if (!frame) return std::nullopt;
  return EngineBinding::WindowPlacement{frame->window(), std::string()};
}

void DesktopHost::PresentWindow(const EngineBinding::WindowPlacement& placement, bool focused) {
  if (DesktopFrame* frame = FrameFor(placement.window); frame && focused) frame->widget()->Activate();
}

// The interface embeds each page itself, and its <embed> goes blank when the
// page's contents go, so the shell keeps nothing beside a page.
void DesktopHost::ReleasePage(const std::string& page) {}

// TODO(crest): dock the inspector's contents into the page card it inspects.
void DesktopHost::DockInspector(const std::string& page, content::WebContents* frontend) {}

void DesktopHost::ReleaseProfile(const std::string& profile) {}

// TODO(crest): extension side panels are cards in the interface's page row.
void DesktopHost::RetractSidePanels(Profile* profile, const std::string& extension, std::optional<int> tab) {}

// --- Hooks the binding and Chromium call (crest_chrome_hooks.h) -------------

namespace {

// The permission requests Crest is answering now. Chromium can raise the same
// requests again inside the answer; they already have it (see
// AnswerPermissionRequests in crest_permission_prompt.h).
const permissions::PermissionPrompt::Delegate* g_answering_permission = nullptr;

}  // namespace

bool IsInstalledProduct() {
  // Decided by where chrome.exe is, as Chromium decides its install mode,
  // so no launch waits on the disk to know.
  static const bool installed = [] {
    base::FilePath exe;
    if (!base::PathService::Get(base::FILE_EXE, &exe)) return false;
    const base::FilePath application = exe.DirName();
    return base::FilePath::CompareEqualIgnoreCase(application.BaseName().value(), FILE_PATH_LITERAL("Application")) &&
           base::FilePath::CompareEqualIgnoreCase(application.DirName().BaseName().value(),
                                                  install_static::kProductPathName);
  }();
  return installed;
}

bool IsEnabled() {
  static const bool enabled = IsInstalledProduct() || base::CommandLine::ForCurrentProcess()->HasSwitch(kHostSwitch);
  return enabled;
}

bool OpenFromLaunch(Profile* profile, const base::CommandLine& command_line, const base::FilePath& cur_dir) {
  // Chromium reads the links and documents as it reads its own launches:
  // the argument after --single-argument whole, a path made a file address
  // against the folder the launch ran in. A tab only an unregistered direct
  // launch scheme would bring is no launch of Crest's.
  std::vector<std::string> urls;
  for (const StartupTab& tab : StartupTabProviderImpl().GetCommandLineTabs(command_line, cur_dir, profile)) {
    if (tab.url.is_valid() && !tab.is_untrusted_launch) urls.push_back(tab.url.spec());
  }
  return DesktopHost::Get().OpenLaunch(std::move(urls));
}

void AddNavigationThrottle(content::NavigationThrottleRegistry& registry) {
  if (IsEnabled()) registry.AddThrottle(EngineBinding::LinkThrottle(registry));
}

// A page the core asked whether it may close answers the core.
bool CompletePageClosePreparation(content::WebContents* contents, bool proceed) {
  return AnswerBeforeUnload(contents, proceed);
}

// A request Crest's permission record covers is asked through the page, so
// the decision is recorded per Space. Others have no prompt in this build yet
// and Chromium settles them as unanswered.
std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
    content::WebContents* contents,
    permissions::PermissionPrompt::Delegate* delegate) {
  if (delegate->ShouldDropCurrentRequestIfCannotShowQuietly()) return nullptr;
  if (g_answering_permission == delegate) return nullptr;
  return EngineBinding::Get().PermissionPrompt(contents, delegate);
}

// Chromium's toasts become a notice in the window in use.
void ShowEngineNotice(const std::u16string& message, ToastId toast) {
  if (!IsEnabled() || !DesktopHost::Get().started() || message.empty()) return;
  DesktopHost::Get().ShowNotice(base::UTF16ToUTF8(message), toast == ToastId::kLinkCopied ? "link" : "confirmation");
}

// Windows has no system translation panel to hand a selection to, as the Mac
// does, and Chromium's partial-translate bubble needs a Views browser frame.
void TranslateSelection(const std::u16string& text) {
  if (!IsEnabled() || !DesktopHost::Get().started() || text.empty()) return;
  DesktopHost::Get().ShowUnavailable(UnavailableFeature::kTranslation);
}

void EnsureCrestUIStarted(Browser* browser) {
  // A review launch names its own engine profile root, so it never opens a
  // Chromium profile another browser on the machine keeps. The installed
  // product keeps Chromium's own folder for Crest's install mode,
  // %LOCALAPPDATA%\Crest\User Data, which no other browser uses.
  CHECK(IsInstalledProduct() || base::CommandLine::ForCurrentProcess()->HasSwitch("user-data-dir"));
  DesktopHost::Get().Start(browser);
}

bool CanCreateEngineBrowser(Profile* profile) {
  if (!IsEnabled() || !DesktopHost::Get().started()) return true;
  return EngineBinding::Get().Browsers().MayCreate(profile);
}

void AnswerPermissionRequests(permissions::PermissionPrompt::Delegate& delegate, bool grants, bool remembers) {
  base::AutoReset<const permissions::PermissionPrompt::Delegate*> answering(&g_answering_permission, &delegate);
  if (grants && remembers) {
    delegate.Accept(std::monostate());
  } else if (grants) {
    delegate.AcceptThisTime(std::monostate());
  } else if (remembers) {
    delegate.Deny(std::monostate());
  } else {
    delegate.Dismiss(std::monostate());
  }
}

}  // namespace crest

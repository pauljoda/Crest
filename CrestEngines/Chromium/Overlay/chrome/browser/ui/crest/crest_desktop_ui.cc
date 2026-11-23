#include "chrome/browser/ui/crest/crest_desktop_ui.h"

#include <UserConsentVerifierInterop.h>
#include <windows.foundation.h>
#include <windows.security.credentials.ui.h>
#include <wrl/client.h>

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <utility>

#include "base/base64.h"
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/i18n/file_util_icu.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/memory/ref_counted_memory.h"
#include "base/numerics/safe_conversions.h"
#include "base/path_service.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "base/uuid.h"
#include "base/win/core_winrt_util.h"
#include "base/win/hstring_reference.h"
#include "base/win/post_async_results.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/extensions/extension_action_runner.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_browsers.h"
#include "chrome/browser/ui/crest/crest_engine_extensions.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "chrome/browser/ui/extensions/extension_popup_types.h"
#include "chrome/browser/ui/views/extensions/extension_popup.h"
#include "chrome/browser/certificate_viewer.h"
#include "chrome/browser/platform_util.h"
#include "chrome/browser/ui/crest/crest_desktop_frame.h"
#include "chrome/browser/ui/crest/crest_desktop_host.h"
#include "chrome/browser/ui/select_file_policy/chrome_select_file_policy.h"
#include "chrome/common/chrome_paths.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_data_source.h"
#include "net/base/filename_util.h"
#include "net/base/load_flags.h"
#include "net/base/net_errors.h"
#include "net/base/url_util.h"
#include "net/cert/x509_certificate.h"
#include "net/http/http_request_headers.h"
#include "net/http/http_response_headers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "net/url_request/redirect_info.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/content_security_policy.mojom.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "third_party/blink/public/common/input/web_mouse_wheel_event.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/accelerators/menu_label_accelerator_util.h"
#include "ui/base/clipboard/scoped_clipboard_writer.h"
#include "ui/base/mojom/menu_source_type.mojom.h"
#include "ui/events/event_constants.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/menus/simple_menu_model.h"
#include "ui/shell_dialogs/select_file_dialog.h"
#include "ui/shell_dialogs/selected_file_info.h"
#include "ui/views/controls/menu/menu_runner.h"
#include "ui/views/controls/webview/webview.h"
#include "ui/views/view.h"
#include "ui/views/widget/widget.h"
#include "ui/views/win/hwnd_util.h"
#include "url/gurl.h"
#include "url/url_constants.h"

namespace crest {

namespace {

constexpr net::NetworkTrafficAnnotationTag kFilterListAnnotation =
    net::DefineNetworkTrafficAnnotation("crest_filter_list_download", R"(
      semantics {
        sender: "Crest filter lists"
        description: "Downloads the filter lists ad blocking and Super Copy use, from the addresses Crest's catalog names and the ones the person subscribed to, as the Mac app downloads them."
        trigger: "When Crest starts, every hour while it runs, and when the person turns on, adds or updates a list."
        data: "The list's address, and the validators of the copy Crest already holds, so an unchanged list is not sent again."
        destination: OTHER
      }
      policy {
        cookies_allowed: NO
        setting: "Ad Blocking's level in Settings: Off asks for no lists but Super Copy's."
      })");

// The person's own search engine, asked as they type: a request they direct,
// wherever it goes, which the network's request policy lets reach Google.
constexpr net::NetworkTrafficAnnotationTag kSearchSuggestionsAnnotation =
    net::DefineNetworkTrafficAnnotation("crest_search_suggestions", R"(
      semantics {
        sender: "Crest command palette"
        description: "Asks the person's search engine for suggestions for what they type in the command palette, as the Mac app asks."
        trigger: "Typing in the command palette, while search suggestions are on."
        data: "The text typed, in the search engine's suggestion address."
        destination: OTHER
      }
      policy {
        cookies_allowed: NO
        setting: "Search suggestions in Settings, and each Space's own choice."
      })");

// The longest list the core keeps (FilterLibrary.MaximumListBytes).
constexpr int64_t kMaximumFetchBytes = 15 * 1024 * 1024;

// Reads one of the interface's files. A path that leaves the interface's
// folder answers nothing.
void ServeInterfaceFile(const base::FilePath& root,
                        const std::string& path,
                        content::WebUIDataSource::GotDataCallback callback) {
  std::string relative = path.substr(0, path.find_first_of("?#"));
  if (relative.empty()) relative = "index.html";
  if (relative.find("..") != std::string::npos || !base::IsStringASCII(relative)) {
    std::move(callback).Run(nullptr);
    return;
  }
  const base::FilePath file = root.AppendASCII(relative).NormalizePathSeparators();
  if (!root.IsParent(file)) {
    std::move(callback).Run(nullptr);
    return;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_BLOCKING},
      base::BindOnce(
          [](const base::FilePath& file) -> scoped_refptr<base::RefCountedMemory> {
            std::string contents;
            if (!base::ReadFileToString(file, &contents)) return nullptr;
            return base::MakeRefCounted<base::RefCountedString>(std::move(contents));
          },
          file),
      std::move(callback));
}

std::vector<uint8_t> BytesAt(const base::ListValue& arguments, size_t index) {
  if (index >= arguments.size() || !arguments[index].is_string()) return {};
  return base::Base64Decode(arguments[index].GetString()).value_or(std::vector<uint8_t>());
}

std::string StringAt(const base::ListValue& arguments, size_t index) {
  return index < arguments.size() && arguments[index].is_string() ? arguments[index].GetString() : std::string();
}

CoreReply Text(const std::string& text) {
  return {CREST_OK, std::vector<uint8_t>(text.begin(), text.end())};
}

// A download's name as a file may take it: its last component, with the
// characters Windows refuses in a name replaced.
base::FilePath SafeFilename(const std::string& suggested) {
  base::FilePath::StringType name = base::FilePath::FromUTF8Unsafe(suggested).BaseName().value();
  base::i18n::ReplaceIllegalCharactersInPath(&name, '_');
  if (name.empty() || name == FILE_PATH_LITERAL(".") || name == FILE_PATH_LITERAL("..")) {
    name = FILE_PATH_LITERAL("download");
  }
  return base::FilePath(name);
}

// A finished download's file, from the destination its record names: a path,
// or a file URL. Empty for anything else.
base::FilePath DownloadPath(const std::string& destination) {
  base::FilePath path;
  if (base::StartsWith(destination, "file:", base::CompareCase::INSENSITIVE_ASCII)) {
    if (!net::FileURLToFilePath(GURL(destination), &path)) return {};
  } else {
    path = base::FilePath::FromUTF8Unsafe(destination);
  }
  return path.IsAbsolute() && !path.ReferencesParent() ? path : base::FilePath();
}

// The system's Save As dialog for one download, which keeps itself until it
// answers with the chosen path, or an empty one when the person cancels.
class SaveDialog : public ui::SelectFileDialog::Listener {
 public:
  static void Show(content::WebContents* owner,
                   const base::FilePath& suggested,
                   base::OnceCallback<void(base::FilePath)> done) {
    auto* dialog = new SaveDialog(std::move(done));
    dialog->dialog_ = ui::SelectFileDialog::Create(dialog, std::make_unique<ChromeSelectFilePolicy>(owner));
    base::FilePath::StringType extension = suggested.Extension();
    if (!extension.empty()) extension.erase(0, 1);
    dialog->dialog_->SelectFile(ui::SelectFileDialog::SELECT_SAVEAS_FILE, u"Save Download", suggested, nullptr, 0,
                                extension, owner->GetTopLevelNativeWindow());
  }

  void FileSelected(const ui::SelectedFileInfo& file, int index) override { Finish(file.file_path); }
  void FileSelectionCanceled() override { Finish(base::FilePath()); }

 private:
  explicit SaveDialog(base::OnceCallback<void(base::FilePath)> done) : done_(std::move(done)) {}
  ~SaveDialog() override {
    if (dialog_) dialog_->ListenerDestroyed();
  }

  void Finish(base::FilePath path) {
    std::move(done_).Run(std::move(path));
    delete this;
  }

  base::OnceCallback<void(base::FilePath)> done_;
  scoped_refptr<ui::SelectFileDialog> dialog_;
};

}  // namespace

// A menu the interface asks for, run as Windows' own context menus are, as
// Chrome's are: the interface describes its items, each {id, title, enabled,
// checked, shortcut {key, control, shift, alt}, submenu} or {separator}, and
// hears which one the person chose, or none.
class InterfaceMenu : public ui::SimpleMenuModel::Delegate {
 public:
  using Done = base::OnceCallback<void(std::optional<std::string>)>;

  InterfaceMenu(const base::ListValue& items, Done done)
      : model_(std::make_unique<ui::SimpleMenuModel>(this)), done_(std::move(done)) {
    Build(*model_, items);
  }

  // Runs the menu with its top left corner at `point`, in screen coordinates.
  void Run(views::Widget* widget, const gfx::Point& point) {
    runner_ = std::make_unique<views::MenuRunner>(
        model_.get(), views::MenuRunner::CONTEXT_MENU | views::MenuRunner::HAS_MNEMONICS,
        base::BindRepeating(&InterfaceMenu::Closed, base::Unretained(this)));
    runner_->RunMenuAt(widget, nullptr, gfx::Rect(point, gfx::Size()), views::MenuAnchorPosition::kTopLeft,
                       ui::mojom::MenuSourceType::kMouse);
  }

  // ui::SimpleMenuModel::Delegate:
  bool IsCommandIdChecked(int command_id) const override { return checked_.contains(command_id); }
  bool IsCommandIdEnabled(int command_id) const override { return !disabled_.contains(command_id); }
  bool GetAcceleratorForCommandId(int command_id, ui::Accelerator* accelerator) const override {
    const auto found = accelerators_.find(command_id);
    if (found == accelerators_.end()) return false;
    *accelerator = found->second;
    return true;
  }
  void ExecuteCommand(int command_id, int event_flags) override {
    if (command_id >= 0 && static_cast<size_t>(command_id) < ids_.size()) chosen_ = ids_[command_id];
  }

 private:
  void Build(ui::SimpleMenuModel& model, const base::ListValue& items) {
    for (const base::Value& entry : items) {
      const base::DictValue* item = entry.GetIfDict();
      if (!item) continue;
      if (item->FindBool("separator").value_or(false)) {
        model.AddSeparator(ui::NORMAL_SEPARATOR);
        continue;
      }
      const std::string* title = item->FindString("title");
      if (!title) continue;
      // An ampersand in a title is the title's own, not a mnemonic.
      const std::u16string label = ui::EscapeMenuLabelAmpersands(base::UTF8ToUTF16(*title));
      const int command = static_cast<int>(ids_.size());
      const std::string* id = item->FindString("id");
      ids_.push_back(id ? *id : std::string());
      if (const base::ListValue* children = item->FindList("submenu")) {
        auto submenu = std::make_unique<ui::SimpleMenuModel>(this);
        Build(*submenu, *children);
        model.AddSubMenu(command, label, submenu.get());
        submenus_.push_back(std::move(submenu));
      } else if (const std::optional<bool> checked = item->FindBool("checked")) {
        model.AddCheckItem(command, label);
        if (*checked) checked_.insert(command);
      } else {
        model.AddItem(command, label);
      }
      if (!item->FindBool("enabled").value_or(true)) disabled_.insert(command);
      if (const base::DictValue* keys = item->FindDict("shortcut")) {
        int flags = ui::EF_NONE;
        if (keys->FindBool("control").value_or(false)) flags |= ui::EF_CONTROL_DOWN;
        if (keys->FindBool("shift").value_or(false)) flags |= ui::EF_SHIFT_DOWN;
        if (keys->FindBool("alt").value_or(false)) flags |= ui::EF_ALT_DOWN;
        accelerators_.emplace(command, ui::Accelerator(static_cast<ui::KeyboardCode>(keys->FindInt("key").value_or(0)), flags));
      }
    }
  }

  // The chosen item, if any, ran before the menu closed; the answer goes once.
  void Closed() {
    if (done_) std::move(done_).Run(chosen_);
  }

  std::unique_ptr<ui::SimpleMenuModel> model_;
  std::vector<std::unique_ptr<ui::SimpleMenuModel>> submenus_;
  // Each command's id as the interface named it, by command.
  std::vector<std::string> ids_;
  std::set<int> disabled_;
  std::set<int> checked_;
  std::map<int, ui::Accelerator> accelerators_;
  std::unique_ptr<views::MenuRunner> runner_;
  std::optional<std::string> chosen_;
  Done done_;
};

CrestDesktopUI::CrestDesktopUI(content::WebUI* web_ui) : content::WebUIController(web_ui) {
  content::WebUIDataSource* source = content::WebUIDataSource::CreateAndAdd(
      web_ui->GetWebContents()->GetBrowserContext(), kCrestDesktopHost);
  source->SetRequestFilter(base::BindRepeating([](const std::string&) { return true; }),
                           base::BindRepeating(&ServeInterfaceFile, DesktopHost::Get().interface_directory()));
  using network::mojom::CSPDirectiveName;
  source->OverrideContentSecurityPolicy(CSPDirectiveName::ScriptSrc, "script-src 'self';");
  source->OverrideContentSecurityPolicy(CSPDirectiveName::StyleSrc, "style-src 'self' 'unsafe-inline';");
  // Tabs show their sites' icons, which come from the sites themselves.
  source->OverrideContentSecurityPolicy(CSPDirectiveName::ImgSrc, "img-src 'self' https: http: data: blob:;");
  source->OverrideContentSecurityPolicy(CSPDirectiveName::FontSrc, "font-src 'self' data:;");
  // The window's pages are surface embeds.
  source->OverrideContentSecurityPolicy(CSPDirectiveName::ObjectSrc, "object-src 'self';");
  source->DisableTrustedTypesCSP();
  web_ui->AddMessageHandler(std::make_unique<DesktopBridge>());
}

CrestDesktopUI::~CrestDesktopUI() = default;

WEB_UI_CONTROLLER_TYPE_IMPL(CrestDesktopUI)

DesktopBridge::DesktopBridge() {
  DesktopHost::Get().AddBridge(this);
}

DesktopBridge::~DesktopBridge() {
  ObserveWidget(nullptr);
  DesktopHost::Get().RemoveBridge(this);
}

void DesktopBridge::OnJavascriptAllowed() {
  content::RenderFrameHost* frame = web_ui()->GetWebContents()->GetPrimaryMainFrame();
  ObserveWidget(frame ? frame->GetRenderWidgetHost() : nullptr);
}

void DesktopBridge::OnJavascriptDisallowed() {
  ObserveWidget(nullptr);
}

void DesktopBridge::ObserveWidget(content::RenderWidgetHost* host) {
  if (observed_widget_ == host) return;
  if (observed_widget_) {
    observed_widget_->RemoveInputEventObserver(this);
    observed_widget_->RemoveObserver(this);
  }
  observed_widget_ = host;
  if (observed_widget_) {
    observed_widget_->AddInputEventObserver(this);
    observed_widget_->AddObserver(this);
  }
}

void DesktopBridge::RenderWidgetHostDestroyed(content::RenderWidgetHost* host) {
  if (host == observed_widget_) ObserveWidget(nullptr);
}

// The page hears a precision touchpad's scroll as wheel events without its
// phases, so it can't tell fingers that rest from fingers that lifted, nor
// the system's momentum from the fingers' own movement. Those the interface
// needs to follow a swipe between Spaces as the Mac's does, so they go to it
// beside the events. A wheel Chromium gave phases to on a timer has none of
// its own, and goes only as the page's event.
void DesktopBridge::OnInputEvent(const content::RenderWidgetHost& host,
                                 const blink::WebInputEvent& event,
                                 InputEventSource) {
  if (event.GetType() != blink::WebInputEvent::Type::kMouseWheel || !IsJavascriptAllowed()) return;
  const auto& wheel = static_cast<const blink::WebMouseWheelEvent&>(event);
  if (wheel.has_synthetic_phase || wheel.delta_units != ui::ScrollGranularity::kScrollByPrecisePixel ||
      (wheel.phase == blink::WebMouseWheelEvent::kPhaseNone &&
       wheel.momentum_phase == blink::WebMouseWheelEvent::kPhaseNone)) {
    return;
  }
  const content::RenderWidgetHostView* view = host.GetView();
  const float scale = view && view->GetDeviceScaleFactor() > 0 ? view->GetDeviceScaleFactor() : 1.f;
  const gfx::PointF position = wheel.PositionInWidget();
  CallJavascriptFunction("crestWheel", base::Value(static_cast<int>(wheel.phase)),
                         base::Value(static_cast<int>(wheel.momentum_phase)), base::Value(-wheel.delta_x / scale),
                         base::Value(-wheel.delta_y / scale), base::Value(position.x() / scale),
                         base::Value(position.y() / scale),
                         base::Value((wheel.TimeStamp() - base::TimeTicks()).InSecondsF()));
}

void DesktopBridge::RegisterMessages() {
  web_ui()->RegisterMessageCallback("crestCore",
                                    base::BindRepeating(&DesktopBridge::OnCall, base::Unretained(this)));
}

void DesktopBridge::OnCall(const base::ListValue& arguments) {
  AllowJavascript();
  if (arguments.size() < 2 || !arguments[1].is_string()) return;
  const std::string& op = arguments[1].GetString();
  if (op == "downloadDestination") {
    ResolveDownloadDestination(arguments[0].Clone(), StringAt(arguments, 2), StringAt(arguments, 3),
                               StringAt(arguments, 4) == "1");
    return;
  }
  if (op == "fetchText") {
    FetchText(arguments[0].Clone(), StringAt(arguments, 2), StringAt(arguments, 3), StringAt(arguments, 4),
              StringAt(arguments, 5));
    return;
  }
  if (op == "runExtension") {
    double x = 0;
    double y = 0;
    double width = 0;
    double height = 0;
    base::StringToDouble(StringAt(arguments, 4), &x);
    base::StringToDouble(StringAt(arguments, 5), &y);
    base::StringToDouble(StringAt(arguments, 6), &width);
    base::StringToDouble(StringAt(arguments, 7), &height);
    Reply(arguments[0], RunExtension(StringAt(arguments, 2), StringAt(arguments, 3),
                                     gfx::Rect(base::ClampRound(x), base::ClampRound(y), base::ClampRound(width),
                                               base::ClampRound(height))));
    return;
  }
  if (op == "menu") {
    double x = 0;
    double y = 0;
    base::StringToDouble(StringAt(arguments, 3), &x);
    base::StringToDouble(StringAt(arguments, 4), &y);
    ShowMenu(arguments[0].Clone(), StringAt(arguments, 2), x, y);
    return;
  }
  if (op == "verifyOwner") {
    VerifyOwner(arguments[0].Clone(), StringAt(arguments, 2));
    return;
  }
  Reply(arguments[0], Answer(op, arguments));
}

void DesktopBridge::VerifyOwner(base::Value id, const std::string& reason) {
  using ABI::Windows::Foundation::IAsyncOperation;
  using ABI::Windows::Security::Credentials::UI::UserConsentVerificationResult;
  // The prompt belongs to the window that asks, so it stands over it and the
  // window waits for it, as the Mac's sheet does.
  DesktopFrame* frame = DesktopHost::Get().FrameFor(Window());
  HWND window = frame && frame->widget() ? views::HWNDForWidget(frame->widget()) : nullptr;
  Microsoft::WRL::ComPtr<IUserConsentVerifierInterop> verifier;
  HRESULT result = window ? base::win::GetActivationFactory<
                                IUserConsentVerifierInterop,
                                RuntimeClass_Windows_Security_Credentials_UI_UserConsentVerifier>(&verifier)
                          : E_FAIL;
  Microsoft::WRL::ComPtr<IAsyncOperation<UserConsentVerificationResult>> verification;
  if (SUCCEEDED(result)) {
    result = verifier->RequestVerificationForWindowAsync(
        window, base::win::HStringReference(base::UTF8ToWide(reason).c_str()).Get(),
        __uuidof(IAsyncOperation<UserConsentVerificationResult>), &verification);
  }
  if (SUCCEEDED(result)) {
    base::WeakPtr<DesktopBridge> bridge = weak_factory_.GetWeakPtr();
    result = base::win::PostAsyncHandlers(
        verification.Get(),
        base::BindOnce(
            [](base::WeakPtr<DesktopBridge> bridge, base::Value id, UserConsentVerificationResult answer) {
              if (!bridge) return;
              using enum ABI::Windows::Security::Credentials::UI::UserConsentVerificationResult;
              switch (answer) {
                case UserConsentVerificationResult_Verified:
                  bridge->AnswerOwner(std::move(id), "verified");
                  return;
                case UserConsentVerificationResult_Canceled:
                case UserConsentVerificationResult_RetriesExhausted:
                  bridge->AnswerOwner(std::move(id), "canceled");
                  return;
                case UserConsentVerificationResult_DeviceBusy:
                  bridge->AnswerOwner(std::move(id), "busy");
                  return;
                default:
                  bridge->AnswerOwner(std::move(id), "unavailable");
              }
            },
            bridge, id.Clone()),
        base::BindOnce(
            [](base::WeakPtr<DesktopBridge> bridge, base::Value id, HRESULT) {
              if (bridge) bridge->AnswerOwner(std::move(id), "unavailable");
            },
            bridge, id.Clone()));
  }
  if (FAILED(result)) AnswerOwner(std::move(id), "unavailable");
}

void DesktopBridge::AnswerOwner(base::Value id, std::string_view result) {
  base::DictValue answer;
  answer.Set("result", result);
  Reply(id, Text(base::WriteJson(answer).value_or("{}")));
}

void DesktopBridge::Reply(const base::Value& id, const CoreReply& reply) {
  if (!IsJavascriptAllowed()) return;
  CallJavascriptFunction("crestCoreReply", id, base::Value(reply.status), base::Value(base::Base64Encode(reply.bytes)));
}

void DesktopBridge::ResolveDownloadDestination(base::Value id,
                                               const std::string& prompt,
                                               const std::string& suggested,
                                               bool asks) {
  if (!DesktopHost::Get().ClaimDownloadPrompt(prompt)) {
    Reply(id, Text("{\"taken\":true}"));
    return;
  }
  const base::FilePath path =
      base::PathService::CheckedGet(chrome::DIR_DEFAULT_DOWNLOADS).Append(SafeFilename(suggested));
  auto answer = base::BindOnce(&DesktopBridge::AnswerDownloadDestination, weak_factory_.GetWeakPtr(), std::move(id));
  if (asks) {
    SaveDialog::Show(web_ui()->GetWebContents(), path, std::move(answer));
    return;
  }
  // The Downloads folder, under a name no file there has yet.
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(
          [](const base::FilePath& path) {
            if (!base::CreateDirectory(path.DirName())) return base::FilePath();
            return base::GetUniquePath(path);
          },
          path),
      std::move(answer));
}

void DesktopBridge::AnswerDownloadDestination(base::Value id, base::FilePath path) {
  base::DictValue answer;
  if (path.empty()) {
    answer.Set("path", base::Value());
  } else {
    answer.Set("path", path.AsUTF8Unsafe());
  }
  Reply(id, Text(base::WriteJson(answer).value_or("{}")));
}

void DesktopBridge::ShowMenu(base::Value id, const std::string& items, double x, double y) {
  std::optional<base::ListValue> list = base::JSONReader::ReadList(items, base::JSON_PARSE_RFC);
  DesktopFrame* frame = DesktopHost::Get().FrameFor(Window());
  // One menu runs at a time; another asked for meanwhile answers nothing.
  if (!list || !frame || !frame->web_view() || menu_) {
    Reply(id, Text("null"));
    return;
  }
  // The interface's coordinates are its view's, in CSS pixels, which are
  // DIPs at the interface's zoom.
  gfx::Point point(base::ClampRound(x), base::ClampRound(y));
  views::View::ConvertPointToScreen(frame->web_view(), &point);
  menu_ = std::make_unique<InterfaceMenu>(
      *list, base::BindOnce(&DesktopBridge::AnswerMenu, weak_factory_.GetWeakPtr(), std::move(id)));
  menu_->Run(frame->widget(), point);
}

void DesktopBridge::AnswerMenu(base::Value id, std::optional<std::string> chosen) {
  Reply(id, Text(chosen ? base::WriteJson(base::Value(*chosen)).value_or("null") : "null"));
  // The menu goes once it has finished closing.
  base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, std::move(menu_));
}

CoreReply DesktopBridge::RunExtension(const std::string& extension_id,
                                      const std::string& page_id,
                                      const gfx::Rect& anchor) {
  const auto answer = [](bool ran, bool popup = false, bool panel = false) {
    return Text(base::WriteJson(base::DictValue().Set("ran", ran).Set("popup", popup).Set("panel", panel))
                    .value_or("{}"));
  };
  EngineBinding& binding = EngineBinding::Get();
  // The binding names pages as the core's identities in capitals.
  EnginePage* page = binding.Find(base::ToUpperASCII(page_id));
  content::WebContents* contents = page ? page->web_contents() : nullptr;
  if (!contents) return answer(false);
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  const extensions::Extension* extension = EngineExtensions::Usable(profile, extension_id);
  if (!extension) return answer(false);
  extensions::ExtensionAction* action = extensions::ExtensionActionManager::Get(profile)->GetExtensionAction(*extension);
  // An extension whose files are gone would show Chromium's own error page
  // in its popup; it is unavailable instead, as on the Mac.
  if (!action || !binding.Extensions().For(profile, page->profile()).IsAvailable(*extension, action)) {
    return answer(false);
  }
  // The action runs for the page its Browser shows.
  if (!binding.Browsers().Activate(contents)) return answer(false);
  Browser* browser = binding.Browsers().Holding(contents);
  auto* runner = extensions::ExtensionActionRunner::GetForWebContents(contents);
  if (!browser || !runner) return answer(false);
  // Only the person's click on the extension's own button runs it, granting
  // the page to the extension for this visit, as Chrome's toolbar button does.
  const auto result = runner->RunAction(extension, /*grant_tab_permissions=*/true);
  if (result == extensions::ExtensionAction::ShowAction::kToggleSidePanel) {
    binding.RequestSidePanel(page->key(), extension_id, engine::SidePanelRequest::kToggle);
    return answer(true, false, true);
  }
  if (result != extensions::ExtensionAction::ShowAction::kShowPopup) return answer(true);
  const GURL popup_url = action->GetPopupUrl(sessions::SessionTabHelper::IdForTab(contents).id());
  views::View* anchor_view = popup_url.is_valid() ? PopupAnchor(anchor) : nullptr;
  auto host = anchor_view ? extensions::ExtensionViewHostFactory::CreatePopupHost(*extension, popup_url, browser)
                          : nullptr;
  if (!host) return answer(true);
  ExtensionPopup::ShowPopup(browser, std::move(host), views::BubbleAnchor(anchor_view), views::BubbleBorder::TOP_LEFT,
                            PopupShowAction::kShow, base::DoNothing());
  return answer(true, true);
}

views::View* DesktopBridge::PopupAnchor(const gfx::Rect& rect) {
  DesktopFrame* frame = DesktopHost::Get().FrameFor(Window());
  views::WebView* web_view = frame ? frame->web_view() : nullptr;
  if (!web_view) return nullptr;
  views::View* anchor = popup_anchor_.view();
  if (!anchor || anchor->parent() != web_view) {
    auto view = std::make_unique<views::View>();
    // It only marks a place: the page and the interface keep every event.
    view->SetCanProcessEventsWithinSubtree(false);
    anchor = web_view->AddChildView(std::move(view));
    popup_anchor_.SetView(anchor);
  }
  // The interface's CSS pixels are its view's DIPs at the interface's zoom.
  anchor->SetBoundsRect(rect);
  return anchor;
}

DesktopBridge::Fetch::Fetch() = default;
DesktopBridge::Fetch::Fetch(Fetch&&) = default;
DesktopBridge::Fetch& DesktopBridge::Fetch::operator=(Fetch&&) = default;
DesktopBridge::Fetch::~Fetch() = default;

void DesktopBridge::FetchText(base::Value id,
                              const std::string& address,
                              const std::string& entity_tag,
                              const std::string& last_modified,
                              const std::string& purpose) {
  const GURL url(address);
  const bool suggestions = purpose == "searchSuggestions";
  if (!url.is_valid() || !url.SchemeIs(url::kHttpsScheme) || (!suggestions && purpose != "filterList")) {
    Reply(id, {CREST_INVALID_ARGUMENT, {}});
    return;
  }
  auto request = std::make_unique<network::ResourceRequest>();
  request->url = url;
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DISABLE_CACHE;
  if (!entity_tag.empty()) request->headers.SetHeader(net::HttpRequestHeaders::kIfNoneMatch, entity_tag);
  if (!last_modified.empty()) request->headers.SetHeader(net::HttpRequestHeaders::kIfModifiedSince, last_modified);
  const int fetch = next_fetch_++;
  Fetch& entry = fetches_[fetch];
  entry.id = std::move(id);
  entry.loader = network::SimpleURLLoader::Create(
      std::move(request), suggestions ? kSearchSuggestionsAnnotation : kFilterListAnnotation);
  entry.loader->SetOnRedirectCallback(
      base::BindRepeating(&DesktopBridge::FetchRedirected, weak_factory_.GetWeakPtr(), fetch));
  entry.loader->DownloadToTempFile(g_browser_process->shared_url_loader_factory().get(),
                                   base::BindOnce(&DesktopBridge::FetchDownloaded, weak_factory_.GetWeakPtr(), fetch),
                                   kMaximumFetchBytes);
}

// No one on the network may change what arrives on its way, so a redirect
// away from https ends the fetch. Deleting the loader here is allowed.
void DesktopBridge::FetchRedirected(int fetch,
                                    const GURL&,
                                    const net::RedirectInfo& redirect,
                                    const network::mojom::URLResponseHead&,
                                    std::vector<std::string>*) {
  if (!redirect.new_url.SchemeIs(url::kHttpsScheme)) AnswerFetch(fetch, std::nullopt);
}

void DesktopBridge::FetchDownloaded(int fetch, base::FilePath file) {
  if (file.empty()) {
    AnswerFetch(fetch, std::nullopt);
    return;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(
          [](const base::FilePath& file) -> std::optional<std::string> {
            std::string text;
            const bool read = base::ReadFileToString(file, &text);
            base::DeleteFile(file);
            if (!read) return std::nullopt;
            return text;
          },
          file),
      base::BindOnce(&DesktopBridge::AnswerFetch, weak_factory_.GetWeakPtr(), fetch));
}

void DesktopBridge::AnswerFetch(int fetch, std::optional<std::string> text) {
  auto found = fetches_.find(fetch);
  if (found == fetches_.end()) return;
  Fetch done = std::move(found->second);
  fetches_.erase(found);
  const network::mojom::URLResponseHead* head = done.loader->ResponseInfo();
  const net::HttpResponseHeaders* headers = head ? head->headers.get() : nullptr;
  const int status = headers ? headers->response_code() : 0;
  base::DictValue answer;
  answer.Set("status", status);
  answer.Set("tooLarge", done.loader->NetError() == net::ERR_INSUFFICIENT_RESOURCES);
  // Only a successful response's body is the answer, and only as UTF-8.
  if (text && status >= 200 && status < 300 && base::IsStringUTF8AllowingNoncharacters(*text)) {
    answer.Set("text", std::move(*text));
  } else {
    answer.Set("text", base::Value());
  }
  const auto header = [headers](std::string_view name) {
    std::optional<std::string> value = headers ? headers->GetNormalizedHeader(name) : std::nullopt;
    return value ? base::Value(std::move(*value)) : base::Value();
  };
  answer.Set("entityTag", header("ETag"));
  answer.Set("lastModified", header("Last-Modified"));
  Reply(done.id, Text(base::WriteJson(answer).value_or("{}")));
}

CoreReply DesktopBridge::Answer(const std::string& op, const base::ListValue& arguments) {
  DesktopHost& host = DesktopHost::Get();
  if (op == "hello") {
    base::DictValue hello;
    hello.Set("window", Window());
    hello.Set("userData", base::PathService::CheckedGet(chrome::DIR_USER_DATA).AsUTF8Unsafe());
    // A precision touchpad's phases arrive as crestWheel, so the interface
    // follows its swipes by them rather than by the page's wheel events.
    hello.Set("wheelPhases", true);
    if (DesktopFrame* frame = host.FrameFor(Window())) {
      hello.Set("frame", frame->State());
      hello.Set("launch", frame->launches());
    }
    return Text(base::WriteJson(hello).value_or("{}"));
  }
  if (op == "shortcuts") {
    std::optional<base::ListValue> list = base::JSONReader::ReadList(StringAt(arguments, 2), base::JSON_PARSE_RFC);
    if (!list) return {CREST_INVALID_ARGUMENT, {}};
    std::vector<Shortcut> shortcuts;
    for (const base::Value& entry : *list) {
      const base::DictValue* fields = entry.GetIfDict();
      const std::string* command = fields ? fields->FindString("command") : nullptr;
      const std::optional<int> key = fields ? fields->FindInt("key") : std::nullopt;
      if (!command || !key) return {CREST_INVALID_ARGUMENT, {}};
      const auto flag = [fields](const char* name) { return fields->FindBool(name).value_or(false); };
      shortcuts.push_back({*command, *key, flag("control"), flag("shift"), flag("alt"), flag("beforePage"),
                           flag("secondPress"), flag("yieldsToText")});
    }
    shortcuts_ = std::move(shortcuts);
    return {CREST_OK, {}};
  }
  if (op == "create") return host.Create(BytesAt(arguments, 2), BytesAt(arguments, 3));
  if (op == "dispatch") return host.Dispatch(this, BytesAt(arguments, 2));
  if (op == "query") return host.Query(BytesAt(arguments, 2));
  if (op == "registerEngine") return host.RegisterEngine(BytesAt(arguments, 2), BytesAt(arguments, 3));
  if (op == "request") return host.Request(BytesAt(arguments, 2));
  if (op == "embed") return Text(host.EmbedPage(StringAt(arguments, 2)));
  if (op == "copy") {
    // Text the interface copies: an address Super Copy made (the core's
    // LinkToCopy), or an answer such as the palette's calculator gives.
    ui::ScopedClipboardWriter(ui::ClipboardBuffer::kCopyPaste).WriteText(base::UTF8ToUTF16(StringAt(arguments, 2)));
    return {CREST_OK, {}};
  }
  if (op == "certificate") {
    // A page's certificate chain, leaf first, as its engine answered it
    // (PageCertificates), in the system's own certificate dialog over this
    // window, as the Mac shows its certificate panel.
    std::vector<std::string> certificates;
    for (size_t index = 2; index < arguments.size(); ++index) {
      const std::vector<uint8_t> der = BytesAt(arguments, index);
      if (der.empty()) return {CREST_INVALID_ARGUMENT, {}};
      certificates.emplace_back(der.begin(), der.end());
    }
    const std::vector<std::string_view> chain(certificates.begin(), certificates.end());
    scoped_refptr<net::X509Certificate> certificate =
        chain.empty() ? nullptr : net::X509Certificate::CreateFromDERCertChain(chain);
    content::WebContents* contents = web_ui()->GetWebContents();
    if (!certificate || !contents) return {CREST_INVALID_ARGUMENT, {}};
    ShowCertificateViewerForClientAuth(contents, contents->GetTopLevelNativeWindow(), certificate.get());
    return {CREST_OK, {}};
  }
  if (op == "openDownload" || op == "showDownload") {
    const base::FilePath path = DownloadPath(StringAt(arguments, 2));
    if (path.empty()) return {CREST_INVALID_ARGUMENT, {}};
    if (op == "openDownload") {
      platform_util::OpenItem(host.interface_profile(), path, platform_util::OPEN_FILE, base::DoNothing());
    } else {
      platform_util::ShowItemInFolder(host.interface_profile(), path);
    }
    return {CREST_OK, {}};
  }
  if (op == "window") {
    DesktopFrame* frame = host.FrameFor(Window());
    const std::string action = StringAt(arguments, 2);
    // The saved window a launch reopens, by the identity the core keeps.
    const std::string saved = base::ToUpperASCII(StringAt(arguments, 3));
    const bool names_free_window = base::Uuid::ParseCaseInsensitive(saved).is_valid() && !host.FrameFor(saved);
    if (action == "new") {
      host.OpenWindow();
    } else if (action == "open" && names_free_window) {
      host.OpenWindow(saved, /*activates=*/false);
    } else if (frame && action == "adopt" && names_free_window && frame->launches()) {
      frame->Adopt(saved);
    } else if (frame && action == "minimize") {
      frame->widget()->Minimize();
    } else if (frame && action == "maximize") {
      frame->widget()->IsMaximized() ? frame->widget()->Restore() : frame->widget()->Maximize();
    } else if (frame && action == "close") {
      // The interface told the core; the window goes.
      frame->Finish();
    } else if (frame && action == "requestClose") {
      frame->widget()->Close();
    } else {
      return {CREST_INVALID_ARGUMENT, {}};
    }
    return {CREST_OK, {}};
  }
  return {CREST_INVALID_ARGUMENT, {}};
}

std::string DesktopBridge::Window() {
  if (!web_ui()) return {};
  if (DesktopFrame* frame = DesktopHost::Get().FrameForContents(web_ui()->GetWebContents())) return frame->window();
  std::string window;
  net::GetValueForKeyInQuery(web_ui()->GetWebContents()->GetVisibleURL(), "window", &window);
  return window;
}

void DesktopBridge::CloseRequested(bool last, base::ListValue stack, base::ListValue pages) {
  CallJavascriptFunction("crestCloseRequested", base::Value(last), base::Value(std::move(stack)),
                         base::Value(std::move(pages)));
}

void DesktopBridge::WindowState(const base::DictValue& state) {
  if (!IsJavascriptAllowed()) return;
  CallJavascriptFunction("crestWindowState", base::Value(state.Clone()));
}

void DesktopBridge::RunCommand(const std::string& command) {
  if (!IsJavascriptAllowed()) return;
  CallJavascriptFunction("crestShortcut", base::Value(command));
}

void DesktopBridge::PageKept(const std::string& command) {
  if (!IsJavascriptAllowed()) return;
  CallJavascriptFunction("crestPageKept", base::Value(command));
}

void DesktopBridge::Changes(const CoreReply& batch) {
  if (!IsJavascriptAllowed()) return;
  CallJavascriptFunction("crestCoreChanges", base::Value(batch.status), base::Value(base::Base64Encode(batch.bytes)));
}

void DesktopBridge::Presentation(const std::vector<uint8_t>& presentation) {
  if (!IsJavascriptAllowed()) return;
  CallJavascriptFunction("crestEnginePresentation", base::Value(base::Base64Encode(presentation)));
}

void DesktopBridge::Unavailable(int feature) {
  if (!IsJavascriptAllowed()) return;
  CallJavascriptFunction("crestUnavailable", base::Value(feature));
}

void DesktopBridge::Notice(const std::string& message, const std::string& kind) {
  if (!IsJavascriptAllowed()) return;
  CallJavascriptFunction("crestEngineNotice", base::Value(message), base::Value(kind));
}

}  // namespace crest

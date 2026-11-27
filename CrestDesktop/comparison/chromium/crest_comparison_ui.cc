#include "chrome/browser/ui/webui/crest_comparison_ui.h"

#include <map>
#include <memory>
#include <string>

#include "base/base_paths.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/memory/ref_counted_memory.h"
#include "base/path_service.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/thread_pool.h"
#include "base/uuid.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_destroyer.h"
#include "components/input/native_web_keyboard_event.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents_delegate.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "components/surface_embed/browser/surface_embed_handle.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_data_source.h"
#include "content/public/browser/web_ui_message_handler.h"
#include "services/network/public/mojom/content_security_policy.mojom.h"

namespace {

// Comparison builds serve only files bundled beside the comparison executable.
void ServeAsset(const base::FilePath& root, const std::string& request,
                content::WebUIDataSource::GotDataCallback done) {
  std::string name = request.substr(0, request.find_first_of("?#"));
  const base::FilePath relative(name.empty() ? "index.html" : name);
  if (relative.IsAbsolute() || relative.ReferencesParent()) {
    std::move(done).Run(nullptr);
    return;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_BLOCKING},
      base::BindOnce([](base::FilePath file) -> scoped_refptr<base::RefCountedMemory> {
        std::string data;
        if (!base::ReadFileToString(file, &data)) return nullptr;
        return base::MakeRefCounted<base::RefCountedString>(std::move(data));
      }, root.Append(relative)), std::move(done));
}

class ComparisonGuest : public content::WebContentsObserver, public content::WebContentsDelegate {
 public:
  using Notify = base::RepeatingCallback<void(std::string, std::string, std::string, bool)>;
  ComparisonGuest(content::BrowserContext* context, Notify notify)
      : contents_(content::WebContents::Create(content::WebContents::CreateParams(context))),
        notify_(std::move(notify)) {
    Observe(contents_.get());
    contents_->SetDelegate(this);
    id_ = surface_embed::SurfaceEmbedHandle::CreateForWebContents(contents_.get())->id().ToString();
  }
  ~ComparisonGuest() override {
    Observe(nullptr);
    contents_->SetDelegate(nullptr);
  }
  content::BrowserContext* context() const { return contents_->GetBrowserContext(); }
  void HoldEscape(bool hold) { holds_escape_ = hold; }
  const std::string& id() const { return id_; }
  void Load(const GURL& url) {
    content::NavigationController::LoadURLParams params(url);
    contents_->GetController().LoadURLWithParams(params);
  }
 private:
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(
      content::WebContents* source, const input::NativeWebKeyboardEvent& event) override {
    if (holds_escape_ && event.GetType() == blink::WebInputEvent::Type::kRawKeyDown &&
        event.windows_key_code == ui::VKEY_ESCAPE &&
        !(event.GetModifiers() & blink::WebInputEvent::kKeyModifiers)) {
      notify_.Run("escape", "", "", false);
      return content::KeyboardEventProcessingResult::HANDLED;
    }
    return content::KeyboardEventProcessingResult::NOT_HANDLED;
  }
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame())
      notify_.Run("started", handle->GetURL().spec(), "", handle->IsSameDocument());
  }
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && handle->HasCommitted())
      notify_.Run("committed", handle->GetURL().spec(), "", handle->IsSameDocument());
  }
  void OnFirstContentfulPaintInPrimaryMainFrame(base::TimeTicks) override {
    notify_.Run("painted", "", "", false);
  }
  void DidStopLoading() override {
    notify_.Run("finished", contents_->GetLastCommittedURL().spec(),
                base::UTF16ToUTF8(contents_->GetTitle()), false);
  }
  std::unique_ptr<content::WebContents> contents_;
  Notify notify_;
  bool holds_escape_ = false;
  std::string id_;
};

class ComparisonBridge : public content::WebUIMessageHandler {
 public:
  ~ComparisonBridge() override { Reset(); }
  void RegisterMessages() override {
    web_ui()->RegisterMessageCallback("crestComparisonGuest",
        base::BindRepeating(&ComparisonBridge::Handle, base::Unretained(this)));
  }
 private:
  void OnJavascriptDisallowed() override { Reset(); }
  void Reset() {
    guests_.clear();
    while (!profiles_.empty()) {
      auto entry = profiles_.begin();
      Profile* profile = entry->second.get();
      profiles_.erase(entry);
      ProfileDestroyer::DestroyOTRProfileWhenAppropriate(profile);
    }
  }
  Profile* ProfileFor(const std::string& id) {
    auto it = profiles_.find(id);
    if (it != profiles_.end()) return it->second;
    auto* owner = Profile::FromBrowserContext(web_ui()->GetWebContents()->GetBrowserContext())->GetOriginalProfile();
    auto* profile = owner->GetOffTheRecordProfile(Profile::OTRProfileID::CreateUnique("CrestComparison"), true);
    profiles_.emplace(id, profile);
    return profile;
  }
  void Notify(std::string page, std::string event, std::string url, std::string title, bool same) {
    if (IsJavascriptAllowed())
      web_ui()->CallJavascriptFunctionUnsafe("crestComparisonEvent", base::Value(page),
          base::Value(event), base::Value(url), base::Value(title), base::Value(same));
  }
  void Handle(const base::ListValue& args) {
    if (args.size() < 2 || !args[0].is_string() || !args[1].is_string()) return;
    const auto& page = args[1].GetString();
    if (!base::Uuid::ParseCaseInsensitive(page).is_valid()) return;
    const auto& action = args[0].GetString();
    auto it = guests_.find(page);
    if (action == "erase" || action == "create") {
      if (args.size() != 3 || !args[2].is_string() ||
          !base::Uuid::ParseCaseInsensitive(args[2].GetString()).is_valid()) return;
    }
    if (action == "erase") {
      AllowJavascript();
      auto profile = profiles_.find(args[2].GetString());
      if (profile != profiles_.end()) {
        for (auto guest = guests_.begin(); guest != guests_.end();) {
          if (guest->second->context() != profile->second) {
            ++guest;
            continue;
          }
          auto closed = guest->first;
          guest = guests_.erase(guest);
          Notify(closed, "closed", "", "", false);
        }
        auto* removed = profile->second.get();
        profiles_.erase(profile);
        ProfileDestroyer::DestroyOTRProfileWhenAppropriate(removed);
      }
      Notify(page, "erased", "true", "", false);
    } else if (action == "create" && it == guests_.end()) {
      AllowJavascript();
      auto guest = std::make_unique<ComparisonGuest>(
          ProfileFor(args[2].GetString()),
          base::BindRepeating(&ComparisonBridge::Notify, base::Unretained(this), page));
      auto id = guest->id();
      guests_.emplace(page, std::move(guest));
      Notify(page, "created", id, "", false);
    } else if (it != guests_.end() && action == "load" && args.size() == 3 && args[2].is_string()) {
      GURL url(args[2].GetString());
      if (url.is_valid() && (url.SchemeIsHTTPOrHTTPS() || url.IsAboutBlank() ||
                             url.spec().starts_with("data:text/html")))
        it->second->Load(url);
      else
        Notify(page, "unsupported", args[2].GetString(), "", false);
    } else if (it != guests_.end() && (action == "holdEscape" || action == "releaseEscape")) {
      it->second->HoldEscape(action == "holdEscape");
    } else if (it != guests_.end() && action == "close") {
      guests_.erase(it);
    }
  }
  std::map<std::string, raw_ptr<Profile>> profiles_;
  std::map<std::string, std::unique_ptr<ComparisonGuest>> guests_;
};
}  // namespace

WEB_UI_CONTROLLER_TYPE_IMPL(CrestComparisonUI)

CrestComparisonUI::CrestComparisonUI(content::WebUI* web_ui) : content::WebUIController(web_ui) {
  auto* source = content::WebUIDataSource::CreateAndAdd(
      web_ui->GetWebContents()->GetBrowserContext(), "crest-comparison");
  auto root = base::PathService::CheckedGet(base::DIR_EXE).DirName().AppendASCII("Resources/CrestComparison");
  source->SetRequestFilter(base::BindRepeating([](const std::string&) { return true; }),
                           base::BindRepeating(&ServeAsset, root));
  using network::mojom::CSPDirectiveName;
  source->OverrideContentSecurityPolicy(CSPDirectiveName::ScriptSrc, "script-src 'self';");
  source->OverrideContentSecurityPolicy(CSPDirectiveName::StyleSrc, "style-src 'self' 'unsafe-inline';");
  source->OverrideContentSecurityPolicy(CSPDirectiveName::ImgSrc, "img-src 'self' data: blob: https:;");
  source->OverrideContentSecurityPolicy(CSPDirectiveName::FontSrc, "font-src 'self' data:;");
  source->OverrideContentSecurityPolicy(CSPDirectiveName::ObjectSrc, "object-src 'self';");
  source->OverrideContentSecurityPolicy(CSPDirectiveName::TrustedTypes, "trusted-types svelte-trusted-html;");
  unsigned port = 0;
  if (base::StringToUint(base::CommandLine::ForCurrentProcess()->GetSwitchValueASCII("crest-comparison-port"), &port)
      && port > 0 && port <= 65535)
    source->OverrideContentSecurityPolicy(CSPDirectiveName::ConnectSrc,
        "connect-src 'self' ws://127.0.0.1:" + base::NumberToString(port) + ";");
  web_ui->AddMessageHandler(std::make_unique<ComparisonBridge>());
}

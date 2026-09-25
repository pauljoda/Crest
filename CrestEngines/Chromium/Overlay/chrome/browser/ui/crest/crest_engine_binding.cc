#include "chrome/browser/ui/crest/crest_engine_binding.h"

#include <algorithm>
#include <cstring>
#include <type_traits>
#include <utility>
#include <variant>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "url/gurl.h"

namespace crest {

std::string GuidText(const engine::Guid& guid) {
  static constexpr char kDigits[] = "0123456789ABCDEF";
  std::string text;
  text.reserve(36);
  for (size_t index = 0; index < guid.size(); ++index) {
    if (index == 4 || index == 6 || index == 8 || index == 10) {
      text.push_back('-');
    }
    text.push_back(kDigits[guid[index] >> 4]);
    text.push_back(kDigits[guid[index] & 0x0f]);
  }
  return text;
}

// static
EngineBinding& EngineBinding::Get() {
  static base::NoDestructor<EngineBinding> binding;
  return *binding;
}

EngineBinding::EngineBinding() = default;
EngineBinding::~EngineBinding() = default;

crest_engine_binding_t EngineBinding::Table() {
  return crest_engine_binding_t{this, &EngineBinding::Attach, &EngineBinding::Run};
}

// static
const std::array<uint8_t, 32>& EngineBinding::Fingerprint() {
  return engine::kFingerprint;
}

crest_engine_pages_t EngineBinding::Pages() {
  return crest_engine_pages_t{this, &EngineBinding::Request, &EngineBinding::Release, &EngineBinding::PresentTo};
}

void EngineBinding::SetShell(Shell* shell) {
  shell_ = shell;
}

void EngineBinding::Dispose() {
  disposing_ = true;
  queue_.clear();
  due_.clear();
  for (auto& [key, page] : pages_) {
    page->Stop();
  }
  pages_.clear();
}

// The core's side.

// static
void CREST_CALL EngineBinding::Attach(void* context, uint64_t app, uint64_t engine, crest_engine_report_t report) {
  auto* binding = static_cast<EngineBinding*>(context);
  binding->app_ = app;
  binding->engine_ = engine;
  binding->report_ = report;
}

// static
void CREST_CALL EngineBinding::Run(void* context, const uint8_t* command, size_t length) {
  auto decoded = engine::Decode<engine::EngineCommand>(command, length);
  // The core and this binding registered against one engine contract, so a
  // command that does not decode is a build bug.
  CHECK(decoded) << "The core's engine command does not decode. Rebuild the engine.";
  auto* binding = static_cast<EngineBinding*>(context);
  // The core delivers on the thread that sent the intent or report that
  // caused a command, which is the UI thread; anything else waits for it.
  if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI)) {
    content::GetUIThreadTaskRunner({})->PostTask(
        FROM_HERE, base::BindOnce(&EngineBinding::Perform, binding->weak_factory_.GetWeakPtr(), std::move(*decoded)));
    return;
  }
  binding->Perform(std::move(*decoded));
}

void EngineBinding::Perform(engine::EngineCommand command) {
  if (disposing_) {
    return;
  }
  if (const auto* creation = std::get_if<engine::CreatePage>(&command)) {
    Create(*creation, /*standalone=*/false);
  } else if (const auto* loading = std::get_if<engine::LoadPage>(&command)) {
    Load(GuidText(loading->page_id), loading->url);
  } else if (const auto* closing = std::get_if<engine::ClosePage>(&command)) {
    Close(*closing);
  }
}

// Creates the page's WebContents on a task of its own: the command arrives
// on the stack of whatever opened the page, and a page the engine offered
// may still claim it as its own first.
void EngineBinding::Create(const engine::CreatePage& creation, bool standalone) {
  const std::string key = GuidText(creation.page_id);
  if (pages_.contains(key)) {
    if (!standalone) {
      Report(engine::PageCreationFailed{.page_id = creation.page_id});
    }
    return;
  }
  pages_.emplace(key, std::make_unique<EnginePage>(*this, creation, standalone));
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&EngineBinding::CreateNow, weak_factory_.GetWeakPtr(), key));
}

void EngineBinding::CreateNow(const std::string& key) {
  EnginePage* page = Find(key);
  if (!page || page->phase() != EnginePage::Phase::kCreating || !shell_ || disposing_) {
    return;
  }
  shell_->CreateContents(key, page->profile(), page->is_private(), page->window(),
                         base::BindOnce(&EngineBinding::Created, weak_factory_.GetWeakPtr(), key));
}

void EngineBinding::Created(const std::string& key, content::WebContents* contents) {
  EnginePage* page = Find(key);
  if (!page || page->phase() != EnginePage::Phase::kCreating) {
    // The page closed, or became an offered one, while its profile loaded.
    if (contents && shell_) {
      shell_->DestroyContents(key);
    }
    return;
  }
  if (!contents) {
    const engine::Guid id = page->id();
    const bool standalone = page->standalone();
    pages_.erase(key);
    if (shell_) {
      shell_->CreationFailed(key);
    }
    if (!standalone) {
      Report(engine::PageCreationFailed{.page_id = id});
    }
    return;
  }
  Live(*page, contents);
}

bool EngineBinding::Adopt(const std::string& key, const std::string& token) {
  EnginePage* page = Find(key);
  if (!page || page->phase() != EnginePage::Phase::kCreating || !shell_ || disposing_) {
    return false;
  }
  page->set_phase(EnginePage::Phase::kAdopting);
  content::WebContents* contents = shell_->AdoptContents(key, token, page->profile());
  if (!contents) {
    page->set_phase(EnginePage::Phase::kCreating);
    return false;
  }
  Live(*page, contents);
  return true;
}

// The page has its WebContents: the platform presents it, the core hears the
// page is live, and then it loads what it was asked to.
void EngineBinding::Live(EnginePage& page, content::WebContents* contents) {
  page.Start(contents);
  if (shell_) {
    shell_->ContentsCreated(page.key());
  }
  if (!page.standalone()) {
    Report(engine::PageCreated{.page_id = page.id()});
  }
  page.LoadPending();
}

void EngineBinding::Close(const engine::ClosePage& closing) {
  const std::string key = GuidText(closing.page_id);
  if (auto page = pages_.extract(key)) {
    if (auto token = page.mapped()->TakeStagedToken()) {
      DiscardStagedNavigation(*token);
    }
    page.mapped()->Stop();
  }
  std::erase(due_, key);
  if (shell_) {
    shell_->DestroyContents(key);
  }
  Report(engine::PageClosed{.page_id = closing.page_id});
}

void EngineBinding::PageLost(const std::string& key) {
  EnginePage* page = Find(key);
  if (!page) {
    return;
  }
  // The engine closed the page on its own, as `window.close()` does. The
  // page is still inside its own teardown, so it is let go of afterwards.
  if (!page->standalone()) {
    Report(engine::PageClosed{.page_id = page->id()});
  }
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&EngineBinding::Forget, weak_factory_.GetWeakPtr(), key));
}

void EngineBinding::Forget(const std::string& key) {
  EnginePage* page = Find(key);
  if (!page || page->phase() != EnginePage::Phase::kGone) {
    return;
  }
  if (auto token = page->TakeStagedToken()) {
    DiscardStagedNavigation(*token);
  }
  std::erase(due_, key);
  pages_.erase(key);
}

// The platform's side.

bool EngineBinding::Stage(const std::string& key, const std::string& token, const std::string& url) {
  EnginePage* page = Find(key);
  return page && page->Stage(token, url);
}

void EngineBinding::Load(const std::string& key, const std::string& url) {
  if (EnginePage* page = Find(key)) {
    page->Load(url);
  }
}

void EngineBinding::StateChanged(const std::string& key) {
  if (EnginePage* page = Find(key)) {
    page->StateChanged();
  }
}

bool EngineBinding::LoadStagedNavigation(const std::string& key, const std::string& token, const GURL& url) {
  return shell_ && shell_->LoadStagedNavigation(key, token, url);
}

void EngineBinding::DiscardStagedNavigation(const std::string& token) {
  if (shell_) {
    shell_->DiscardStagedNavigation(token);
  }
}

engine::PageMediaActivity EngineBinding::MediaActivity(const std::string& key) {
  return shell_ ? shell_->MediaActivity(key) : engine::PageMediaActivity::kNone;
}

// The platform's direct path.

// static
crest_status_t CREST_CALL EngineBinding::Request(void* context, const uint8_t* request, size_t length,
                                                 crest_buffer_t* out) {
  if (!out) {
    return CREST_INVALID_ARGUMENT;
  }
  *out = crest_buffer_t{nullptr, 0};
  auto decoded = engine::Decode<engine::PageRequest>(request, length);
  if (!decoded) {
    return CREST_INVALID_MESSAGE;
  }
  const std::vector<uint8_t> answer = static_cast<EngineBinding*>(context)->Answer(*decoded);
  out->bytes = new uint8_t[answer.size()];
  out->length = answer.size();
  std::memcpy(out->bytes, answer.data(), answer.size());
  return CREST_OK;
}

// static
void CREST_CALL EngineBinding::Release(void*, crest_buffer_t* buffer) {
  if (!buffer) {
    return;
  }
  delete[] buffer->bytes;
  *buffer = crest_buffer_t{nullptr, 0};
}

// static
void CREST_CALL EngineBinding::PresentTo(void* context, crest_engine_present_t present, void* ui) {
  auto* binding = static_cast<EngineBinding*>(context);
  binding->present_ = present;
  binding->ui_ = ui;
}

// Hands each request to its own handler, which answers with the type the
// contract names for it.
std::vector<uint8_t> EngineBinding::Answer(const engine::PageRequest& request) {
  return std::visit(
      [this](const auto& message) {
        using Message = std::decay_t<decltype(message)>;
        auto answer = Handle(message);
        static_assert(std::is_same_v<decltype(answer), typename engine::PageRequestAnswer<Message>::Type>,
                      "A request answers with the type its contract names.");
        return engine::Encode(answer);
      },
      request);
}

bool EngineBinding::Handle(const engine::GoToHistoryOffset& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page && page->GoToOffset(request.offset);
}

bool EngineBinding::Handle(const engine::ReloadPage& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page && page->Reload(request.bypasses_cache);
}

bool EngineBinding::Handle(const engine::StopLoading& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page && page->StopLoading();
}

bool EngineBinding::Handle(const engine::ZoomPage& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page && page->Zoom(request.factor);
}

bool EngineBinding::Handle(const engine::FindInPage& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page && page->Find(request.query, request.backwards, request.case_sensitive);
}

bool EngineBinding::Handle(const engine::CapturePage& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page && page->Capture(request.capture_id, request.area, request.width);
}

bool EngineBinding::Handle(const engine::ExportPage& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page && page->Export(request.export_id, request.format, request.width);
}

engine::InteractionState EngineBinding::Handle(const engine::SaveInteractionState& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return engine::InteractionState{.state = page ? page->SaveInteractionState() : std::nullopt};
}

bool EngineBinding::Handle(const engine::RestoreInteractionState& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page && page->Restore(request.state, request.expected_url);
}

bool EngineBinding::Handle(const engine::MovePageToWindow& request) {
  const std::string key = GuidText(request.page_id);
  EnginePage* page = Find(key);
  return page && page->phase() == EnginePage::Phase::kLive && shell_ &&
         shell_->MoveToWindow(key, GuidText(request.window_id));
}

bool EngineBinding::Handle(const engine::ShowPage& request) {
  const std::string key = GuidText(request.page_id);
  EnginePage* page = Find(key);
  if (!page || !page->Show()) {
    return false;
  }
  if (shell_) {
    shell_->VisibilityChanged(key, true);
  }
  return true;
}

bool EngineBinding::Handle(const engine::HidePage& request) {
  const std::string key = GuidText(request.page_id);
  EnginePage* page = Find(key);
  if (!page) {
    return false;
  }
  if (shell_) {
    shell_->VisibilityChanged(key, false);
  }
  return page->Hide();
}

engine::PageIconImage EngineBinding::Handle(const engine::PageIcon& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return engine::PageIconImage{.image = page ? page->icon() : std::nullopt};
}

// An engine page Settings shows is created like any other, in its window's
// Browser, and loads its address once it exists; the core never hears of it.
bool EngineBinding::Handle(const engine::OpenStandalonePage& request) {
  if (disposing_ || pages_.contains(GuidText(request.page_id))) {
    return false;
  }
  Create(engine::CreatePage{.page_id = request.page_id,
                            .profile_id = request.profile_id,
                            .is_private = false,
                            .window_id = request.window_id},
         /*standalone=*/true);
  Load(GuidText(request.page_id), request.url);
  return true;
}

bool EngineBinding::Handle(const engine::CloseStandalonePage& request) {
  const std::string key = GuidText(request.page_id);
  EnginePage* page = Find(key);
  if (!page || !page->standalone()) {
    return false;
  }
  page->Stop();
  pages_.erase(key);
  std::erase(due_, key);
  if (shell_) {
    shell_->DestroyContents(key);
  }
  return true;
}

// Reports and presentations.

void EngineBinding::Report(engine::EngineEvent event) {
  if (disposing_ || !report_) {
    return;
  }
  queue_.push_back(Outgoing{.to_core = true, .message = engine::Encode(event)});
  ScheduleFlush();
}

void EngineBinding::Present(engine::EnginePresentation presentation) {
  if (disposing_ || !present_) {
    return;
  }
  queue_.push_back(Outgoing{.to_core = false, .message = engine::Encode(presentation)});
  ScheduleFlush();
}

void EngineBinding::ReportStateSoon(const std::string& key) {
  if (disposing_ || !report_) {
    return;
  }
  if (EnginePage* page = Find(key); page && page->standalone()) {
    return;
  }
  if (std::find(due_.begin(), due_.end(), key) == due_.end()) {
    due_.push_back(key);
  }
  ScheduleFlush();
}

void EngineBinding::ScheduleFlush() {
  if (flush_posted_ || flushing_) {
    return;
  }
  flush_posted_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&EngineBinding::Flush, weak_factory_.GetWeakPtr()));
}

// Sends what is queued, oldest first, then the snapshots due this turn. A
// report can make the core deliver a command, which can queue more; those go
// out in the same pass.
void EngineBinding::Flush() {
  flush_posted_ = false;
  flushing_ = true;
  while (!disposing_ && (!queue_.empty() || !due_.empty())) {
    if (queue_.empty()) {
      std::vector<std::string> due = std::move(due_);
      due_.clear();
      for (const std::string& key : due) {
        if (EnginePage* page = Find(key)) {
          page->ReportState();
        }
      }
      continue;
    }
    Outgoing next = std::move(queue_.front());
    queue_.pop_front();
    if (!next.to_core) {
      if (present_) {
        present_(ui_, next.message.data(), next.message.size());
      }
      continue;
    }
    const crest_status_t status = report_(app_, engine_, next.message.data(), next.message.size());
    // A report is never refused; any other answer is a build bug.
    DCHECK(status == CREST_OK || status == CREST_INVALID_HANDLE) << "The core refused an engine report: " << status;
  }
  flushing_ = false;
}

EnginePage* EngineBinding::Find(const std::string& key) {
  auto found = pages_.find(key);
  return found == pages_.end() ? nullptr : found->second.get();
}

}  // namespace crest

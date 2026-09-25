#include "chrome/browser/ui/crest/crest_engine_page.h"

#include <algorithm>
#include <cmath>
#include <utility>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/memory/ref_counted_memory.h"
#include "base/pickle.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_documents.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "components/security_state/content/security_state_tab_helper.h"
#include "components/security_state/core/security_state.h"
#include "components/sessions/content/content_serialized_navigation_builder.h"
#include "components/sessions/core/serialized_navigation_entry.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "components/zoom/zoom_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/restore_type.h"
#include "content/public/browser/web_contents.h"
#include "net/base/net_errors.h"
#include "net/cert/cert_status_flags.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/base/page_transition_types.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"

namespace crest {

namespace {

constexpr char kEngineScheme[] = "chrome://";
constexpr char kCrestScheme[] = "crest://";

// The saved navigation history's own spelling, and its limits: the entries a
// page may keep, the bytes one entry may take and the bytes of the whole.
constexpr char kInteractionStateMagic[] = "crest.navigation.v1";
constexpr int kInteractionStateEntries = 100;
constexpr size_t kInteractionStateEntryBytes = 64 * 1024;
constexpr size_t kInteractionStateBytes = 2 * 1024 * 1024;
// The largest icon image the page reports.
constexpr size_t kIconBytes = 512 * 1024;
// The zoom factors a page takes.
constexpr double kMinimumZoom = 0.25;
constexpr double kMaximumZoom = 5;
// The widest capture, in points, and how long the compositor has to answer.
constexpr double kMaximumCaptureWidth = 16384;
constexpr base::TimeDelta kCaptureTimeout = base::Seconds(2);

std::string ReplacingScheme(std::string_view value, std::string_view from, std::string_view to) {
  if (value.size() < from.size() ||
      !base::EqualsCaseInsensitiveASCII(value.substr(0, from.size()), from)) {
    return std::string(value);
  }
  // Escaped paths, queries and fragments stay as they are, byte for byte.
  return std::string(to) + std::string(value.substr(from.size()));
}

// Why a navigation failed, by Chromium's `net::Error` code, in the terms both
// engines report.
engine::NavigationError NavigationErrorFor(int code) {
  if (code <= net::ERR_CERT_COMMON_NAME_INVALID && code >= -299) {
    return engine::NavigationError::kSecureConnectionFailed;
  }
  switch (code) {
    case net::ERR_INTERNET_DISCONNECTED:
      return engine::NavigationError::kOffline;
    case net::ERR_TIMED_OUT:
    case net::ERR_CONNECTION_TIMED_OUT:
      return engine::NavigationError::kTimedOut;
    case net::ERR_NAME_NOT_RESOLVED:
    case net::ERR_NAME_RESOLUTION_FAILED:
      return engine::NavigationError::kCannotFindServer;
    case net::ERR_CONNECTION_REFUSED:
    case net::ERR_CONNECTION_FAILED:
    case net::ERR_ADDRESS_UNREACHABLE:
      return engine::NavigationError::kCannotConnect;
    case net::ERR_CONNECTION_CLOSED:
    case net::ERR_CONNECTION_RESET:
    case net::ERR_CONNECTION_ABORTED:
    case net::ERR_NETWORK_CHANGED:
      return engine::NavigationError::kConnectionLost;
    case net::ERR_SSL_PROTOCOL_ERROR:
    case net::ERR_SSL_VERSION_OR_CIPHER_MISMATCH:
      return engine::NavigationError::kSecureConnectionFailed;
    case net::ERR_TOO_MANY_REDIRECTS:
      return engine::NavigationError::kTooManyRedirects;
    case net::ERR_INVALID_URL:
    case net::ERR_DISALLOWED_URL_SCHEME:
    case net::ERR_UNKNOWN_URL_SCHEME:
      return engine::NavigationError::kUnsupportedAddress;
    case net::ERR_BLOCKED_BY_CLIENT:
    case net::ERR_BLOCKED_BY_ADMINISTRATOR:
    case net::ERR_BLOCKED_BY_RESPONSE:
      return engine::NavigationError::kBlocked;
    default:
      return engine::NavigationError::kUnknown;
  }
}

// Whether two addresses name the same document: they are equal, or differ
// only in their fragments.
bool SameDocument(const GURL& lhs, const GURL& rhs) {
  return lhs == rhs || (lhs.is_valid() && rhs.is_valid() && lhs.GetWithoutRef() == rhs.GetWithoutRef());
}

}  // namespace

std::string PresentedURL(const GURL& url) {
  return ReplacingScheme(url.possibly_invalid_spec(), kEngineScheme, kCrestScheme);
}

GURL EngineURL(const std::string& url) {
  return GURL(ReplacingScheme(url, kCrestScheme, kEngineScheme));
}

EnginePage::EnginePage(EngineBinding& binding, const engine::CreatePage& creation, bool standalone)
    : binding_(binding),
      standalone_(standalone),
      id_(creation.page_id),
      key_(GuidText(creation.page_id)),
      profile_(GuidText(creation.profile_id)),
      is_private_(creation.is_private),
      window_(GuidText(creation.window_id)) {}

EnginePage::~EnginePage() {
  Stop();
}

void EnginePage::Start(content::WebContents* contents) {
  Observe(contents);
  phase_ = Phase::kLive;
  if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(contents)) {
    driver->AddObserver(this);
  }
  find_helper_ = find_in_page::FindTabHelper::FromWebContents(contents);
  if (find_helper_) {
    find_helper_->AddObserver(this);
  }
  ApplyZoom();
  UpdateTheme();
  StateChanged();
}

void EnginePage::Stop() {
  settle_timer_.Stop();
  documents_.reset();
  if (find_helper_) {
    find_helper_->RemoveObserver(this);
    find_helper_ = nullptr;
  }
  if (web_contents()) {
    if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents())) {
      driver->RemoveObserver(this);
    }
  }
  Observe(nullptr);
}

// Loads the app asks for.

void EnginePage::Load(const std::string& url) {
  if (staged_ && staged_->url != url) {
    binding_->DiscardStagedNavigation(staged_->token);
    staged_.reset();
  }
  // A load of its own replaces history the page was about to restore.
  pending_state_.reset();
  pending_url_ = url;
  StateChanged();
  pending_load_ = url;
  if (phase_ == Phase::kLive) {
    LoadPending();
  }
}

bool EnginePage::Stage(const std::string& token, const std::string& url) {
  if (phase_ != Phase::kCreating || staged_) {
    return false;
  }
  staged_ = StagedNavigation{token, url};
  return true;
}

bool EnginePage::Restore(std::vector<uint8_t> state, const std::string& expected_url) {
  if (phase_ == Phase::kLive) {
    return RestoreNow(state, expected_url);
  }
  if (phase_ != Phase::kCreating) {
    return false;
  }
  pending_load_ = expected_url;
  pending_state_ = std::move(state);
  return true;
}

void EnginePage::LoadPending() {
  if (!pending_load_) {
    return;
  }
  const std::string url = std::move(*pending_load_);
  pending_load_.reset();
  if (staged_) {
    StagedNavigation staged = std::move(*staged_);
    staged_.reset();
    pending_state_.reset();
    // A stale request is never retried as a bare address, which would lose
    // the initiating frame's security and referrer.
    if (!binding_->LoadStagedNavigation(key_, staged.token, EngineURL(url))) {
      Interrupted();
    }
    return;
  }
  if (pending_state_) {
    std::vector<uint8_t> state = std::move(*pending_state_);
    pending_state_.reset();
    if (RestoreNow(state, url)) {
      return;
    }
  }
  Navigate(url);
}

std::optional<std::string> EnginePage::TakeStagedToken() {
  if (!staged_) {
    return std::nullopt;
  }
  std::string token = std::move(staged_->token);
  staged_.reset();
  return token;
}

void EnginePage::Navigate(const std::string& url) {
  const GURL target = EngineURL(url);
  if (!web_contents() || !target.is_valid()) {
    return;
  }
  web_contents()->GetController().LoadURL(target, content::Referrer(), ui::PAGE_TRANSITION_TYPED,
                                          std::string());
}

// Navigation history.

std::optional<std::vector<uint8_t>> EnginePage::SaveInteractionState() {
  if (!web_contents()) {
    return std::nullopt;
  }
  auto& controller = web_contents()->GetController();
  if (controller.IsInitialNavigation() || !controller.GetLastCommittedEntry() ||
      controller.GetEntryCount() > kInteractionStateEntries || controller.GetLastCommittedEntryIndex() < 0) {
    return std::nullopt;
  }
  base::Pickle pickle;
  pickle.WriteString(kInteractionStateMagic);
  pickle.WriteString(profile_);
  pickle.WriteInt(controller.GetLastCommittedEntryIndex());
  pickle.WriteInt(controller.GetEntryCount());
  for (int index = 0; index < controller.GetEntryCount(); ++index) {
    auto navigation =
        sessions::ContentSerializedNavigationBuilder::FromNavigationEntry(index, controller.GetEntryAtIndex(index));
    base::Pickle entry;
    // Chromium's session serializer leaves out password data.
    navigation.WriteToPickle(kInteractionStateEntryBytes, &entry);
    pickle.WriteData(entry.AsBytes());
    if (pickle.AsBytes().size() > kInteractionStateBytes) {
      return std::nullopt;
    }
  }
  const auto bytes = pickle.AsBytes();
  return std::vector<uint8_t>(bytes.begin(), bytes.end());
}

bool EnginePage::RestoreNow(const std::vector<uint8_t>& state, const std::string& expected_url) {
  if (!web_contents() || state.empty() || state.size() > kInteractionStateBytes) {
    return false;
  }
  auto& controller = web_contents()->GetController();
  // Restoration is only for a new page, never a replacement of live work.
  if (!controller.IsInitialNavigation()) {
    return false;
  }
  auto iterator = base::PickleIterator::WithData(base::span(state));
  std::string magic;
  std::string profile;
  int selected = 0;
  int count = 0;
  if (!iterator.ReadString(&magic) || magic != kInteractionStateMagic || !iterator.ReadString(&profile) ||
      profile != profile_ || !iterator.ReadInt(&selected) || !iterator.ReadInt(&count) || count < 1 ||
      count > kInteractionStateEntries || selected < 0 || selected >= count) {
    return false;
  }
  std::vector<sessions::SerializedNavigationEntry> saved;
  for (int index = 0; index < count; ++index) {
    auto bytes = iterator.ReadData();
    if (!bytes || bytes->size() > kInteractionStateEntryBytes + 4 * 1024) {
      return false;
    }
    auto entry = base::PickleIterator::WithData(*bytes);
    sessions::SerializedNavigationEntry navigation;
    if (!navigation.ReadFromPickle(&entry) || !navigation.virtual_url().is_valid()) {
      return false;
    }
    saved.push_back(std::move(navigation));
  }
  const GURL expected = EngineURL(expected_url);
  if (!iterator.ReachedEnd() || !expected.is_valid() ||
      saved[static_cast<size_t>(selected)].virtual_url().GetWithoutRef() != expected.GetWithoutRef()) {
    return false;
  }
  auto entries =
      sessions::ContentSerializedNavigationBuilder::ToNavigationEntries(saved, web_contents()->GetBrowserContext());
  if (entries.size() != saved.size() ||
      std::any_of(entries.begin(), entries.end(), [](const auto& entry) { return !entry; })) {
    return false;
  }
  web_contents()->Stop();
  controller.DiscardNonCommittedEntries();
  controller.Restore(selected, content::RestoreType::kRestored, &entries);
  controller.LoadIfNecessary();
  StateChanged();
  return true;
}

// The engine's callbacks.

void EnginePage::DidStartNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument()) {
    return;
  }
  loading_navigation_ = navigation->GetNavigationId();
  Started(PresentedURL(navigation->GetURL()));
}

void EnginePage::DidRedirectNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument() ||
      loading_navigation_ != navigation->GetNavigationId()) {
    return;
  }
  pending_url_ = PresentedURL(navigation->GetURL());
  StateChanged();
}

void EnginePage::DidFinishNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame()) {
    return;
  }
  const bool loading = loading_navigation_ == navigation->GetNavigationId();
  if (loading) {
    loading_navigation_.reset();
  }
  // A certificate error commits the engine's own interstitial, which explains
  // the problem and offers to proceed. It is the page, not a failure.
  const bool certificate_error =
      navigation->IsErrorPage() && net::IsCertificateError(navigation->GetNetErrorCode());
  if (navigation->IsErrorPage() && !certificate_error) {
    awaits_finish_ = false;
    Failed(engine::PageFailure{.error = NavigationErrorFor(navigation->GetNetErrorCode()),
                               .url = PresentedURL(navigation->GetURL()),
                               .replaced_document = true,
                               .domain = "net",
                               .code = navigation->GetNetErrorCode()});
    return;
  }
  if (!navigation->HasCommitted()) {
    // A navigation that became a download, was answered with no content or
    // was cancelled loads no document.
    if (loading && !navigation->IsSameDocument()) {
      Interrupted();
    }
    StateChanged();
    return;
  }
  const GURL committed = web_contents()->GetLastCommittedURL();
  if (ShowsInitialBlank(committed)) {
    return;
  }
  UpdateTheme();
  if (navigation->IsSameDocument()) {
    MovedWithinDocument(PresentedURL(committed));
  } else {
    awaits_finish_ = true;
    Committed(PresentedURL(committed));
  }
  NoteTitle();
  FinishIfLoaded();
  StateChanged();
}

void EnginePage::DidStartLoading() {
  StateChanged();
}

void EnginePage::DidStopLoading() {
  NoteTitle();
  FinishIfLoaded();
  StateChanged();
  if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents())) {
    PublishIcon(driver->GetFavicon());
  }
}

void EnginePage::TitleWasSet(content::NavigationEntry* entry) {
  NoteTitle();
  StateChanged();
}

void EnginePage::DidChangeVisibleSecurityState() {
  StateChanged();
}

void EnginePage::DidChangeThemeColor() {
  UpdateTheme();
  StateChanged();
}

void EnginePage::PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) {
  awaits_finish_ = false;
  loading_navigation_.reset();
  Interrupted();
}

void EnginePage::OnAudioStateChanged(bool audible) {
  StateChanged();
}

void EnginePage::MediaStartedPlaying(const MediaPlayerInfo& info, const content::MediaPlayerId& id) {
  StateChanged();
}

void EnginePage::MediaStoppedPlaying(const MediaPlayerInfo& info,
                                     const content::MediaPlayerId& id,
                                     content::WebContentsObserver::MediaStoppedReason reason) {
  StateChanged();
}

void EnginePage::WebContentsDestroyed() {
  settle_timer_.Stop();
  documents_.reset();
  if (find_helper_) {
    find_helper_->RemoveObserver(this);
    find_helper_ = nullptr;
  }
  if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents())) {
    driver->RemoveObserver(this);
  }
  Observe(nullptr);
  phase_ = Phase::kGone;
  binding_->PageLost(key_);
}

void EnginePage::OnFaviconUpdated(favicon::FaviconDriver* driver,
                                  NotificationIconType type,
                                  const GURL& icon_url,
                                  bool icon_url_changed,
                                  const gfx::Image& image) {
  PublishIcon(image);
}

// Navigation events.

void EnginePage::Started(const std::string& url) {
  CancelSettling();
  pending_url_ = url;
  StateChanged();
  Report(engine::NavigationStarted{.page_id = id_, .url = url, .same_document = false});
}

void EnginePage::Committed(const std::string& url) {
  CancelSettling();
  document_url_ = url;
  pending_url_.reset();
  icon_.reset();
  StateChanged();
  Report(engine::NavigationCommitted{.page_id = id_, .url = url, .same_document = false});
}

void EnginePage::Finished(const std::string& url) {
  CancelSettling();
  document_url_ = url;
  pending_url_.reset();
  StateChanged();
  Report(engine::NavigationFinished{.page_id = id_, .url = url, .title = Title()});
}

void EnginePage::Failed(engine::PageFailure failure) {
  CancelSettling();
  pending_url_.reset();
  StateChanged();
  Report(engine::NavigationFailed{.page_id = id_, .failure = std::move(failure)});
}

void EnginePage::Interrupted() {
  pending_url_.reset();
  StateChanged();
}

void EnginePage::MovedWithinDocument(const std::string& url) {
  if (document_url_ == url) {
    return;
  }
  document_url_ = url;
  StateChanged();
  Report(engine::NavigationStarted{.page_id = id_, .url = url, .same_document = true});
  Report(engine::NavigationCommitted{.page_id = id_, .url = url, .same_document = true});
  // A new document still loading finishes the move with its own finish.
  if (loading_navigation_ || awaits_finish_) {
    return;
  }
  CancelSettling();
  settling_url_ = url;
  settle_deadline_ = base::TimeTicks::Now() + kTitleSettleLimit;
  settle_timer_.Start(FROM_HERE, std::min(kTitleSettleInterval, kTitleSettleLimit),
                      base::BindOnce(&EnginePage::Settle, base::Unretained(this)));
}

void EnginePage::TitleChanged() {
  StateChanged();
  if (!settling_url_) {
    return;
  }
  // The wait restarts, never past its limit.
  const base::TimeDelta remaining = settle_deadline_ - base::TimeTicks::Now();
  settle_timer_.Start(FROM_HERE, std::max(base::TimeDelta(), std::min(kTitleSettleInterval, remaining)),
                      base::BindOnce(&EnginePage::Settle, base::Unretained(this)));
}

void EnginePage::NoteTitle() {
  std::string title = Title();
  if (title == reported_title_) {
    return;
  }
  reported_title_ = std::move(title);
  TitleChanged();
}

void EnginePage::FinishIfLoaded() {
  if (!awaits_finish_ || !web_contents() || web_contents()->IsLoading()) {
    return;
  }
  awaits_finish_ = false;
  Finished(PresentedURL(web_contents()->GetLastCommittedURL()));
}

void EnginePage::Settle() {
  if (!settling_url_) {
    return;
  }
  std::string url = std::move(*settling_url_);
  settling_url_.reset();
  Report(engine::NavigationFinished{.page_id = id_, .url = std::move(url), .title = Title()});
}

void EnginePage::CancelSettling() {
  settle_timer_.Stop();
  settling_url_.reset();
}

// The icon.

void EnginePage::PublishIcon(const gfx::Image& image) {
  if (!web_contents() || image.IsEmpty()) {
    return;
  }
  auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents());
  if (!driver) {
    return;
  }
  // An icon for a document the page no longer shows is not this one's.
  const GURL source = driver->GetActiveURL();
  if (source.is_valid() && !SameDocument(source, web_contents()->GetLastCommittedURL())) {
    return;
  }
  auto png = image.As1xPNGBytes();
  if (!png || png->size() == 0 || png->size() > kIconBytes) {
    return;
  }
  icon_ = FoundIcon{std::vector<uint8_t>(png->begin(), png->end()),
                    PresentedURL(source.is_valid() ? source : web_contents()->GetLastCommittedURL())};
  ReportIcon();
}

void EnginePage::UpdateTheme() {
  if (!web_contents()) {
    return;
  }
  std::optional<engine::TabIconAccent> accent;
  if (const auto color = web_contents()->GetThemeColor(); color && SkColorGetA(*color) > 0) {
    accent = engine::TabIconAccent{.red = SkColorGetR(*color) / 255.0,
                                   .green = SkColorGetG(*color) / 255.0,
                                   .blue = SkColorGetB(*color) / 255.0};
  }
  if (accent == accent_) {
    return;
  }
  accent_ = accent;
  ReportIcon();
}

void EnginePage::ReportIcon() {
  if (!icon_) {
    return;
  }
  Report(engine::PageIconChanged{.page_id = id_, .url = icon_->url, .accent = accent_});
}

std::optional<std::vector<uint8_t>> EnginePage::icon() const {
  if (!icon_) {
    return std::nullopt;
  }
  return icon_->png;
}

// What the page shows.

void EnginePage::StateChanged() {
  if (report_due_) {
    return;
  }
  report_due_ = true;
  binding_->ReportStateSoon(key_);
}

void EnginePage::ReportState() {
  report_due_ = false;
  engine::PageSnapshot snapshot = Snapshot();
  if (snapshot == reported_) {
    return;
  }
  reported_ = snapshot;
  Report(engine::PageStateChanged{.page_id = id_, .snapshot = std::move(snapshot)});
}

engine::PageSnapshot EnginePage::Snapshot() const {
  engine::PageSnapshot snapshot{.pending_url = pending_url_};
  if (!web_contents()) {
    return snapshot;
  }
  const GURL visible = web_contents()->GetVisibleURL();
  if (!visible.is_empty() && !ShowsInitialBlank(visible)) {
    snapshot.url = PresentedURL(visible);
  }
  auto& controller = web_contents()->GetController();
  snapshot.title = Title();
  snapshot.is_loading = web_contents()->IsLoading();
  snapshot.can_go_back = controller.CanGoBack();
  snapshot.can_go_forward = controller.CanGoForward();
  snapshot.security = Security();
  snapshot.media = binding_->MediaActivity(key_);
  return snapshot;
}

std::string EnginePage::Title() const {
  return web_contents() ? base::UTF16ToUTF8(web_contents()->GetTitle()) : std::string();
}

// The engine's own verdict on the visible document's connection. Only a
// secure transport with no mixed content and no certificate problem is
// secure; a page the engine flags as malicious outranks everything else, and
// a certificate error outranks mixed content.
engine::PageSecurity EnginePage::Security() const {
  auto* helper = web_contents() ? SecurityStateTabHelper::FromWebContents(web_contents()) : nullptr;
  if (!helper) {
    return engine::PageSecurity::kNone;
  }
  const auto visible = helper->GetVisibleSecurityState();
  const auto level = helper->GetSecurityLevel();
  if (!visible) {
    return engine::PageSecurity::kNone;
  }
  if (visible->malicious_content_status != security_state::MALICIOUS_CONTENT_STATUS_NONE) {
    return engine::PageSecurity::kDangerous;
  }
  if (net::IsCertStatusError(visible->cert_status)) {
    return engine::PageSecurity::kCertificateError;
  }
  // Any other failed load shows Crest's own failure view, not a connection.
  if (visible->is_error_page) {
    return engine::PageSecurity::kNone;
  }
  if (!security_state::IsSchemeCryptographic(visible->url)) {
    return level == security_state::WARNING || level == security_state::DANGEROUS
               ? engine::PageSecurity::kInsecure
               : engine::PageSecurity::kNone;
  }
  // An HTTPS entry that has not connected yet has no connection to judge.
  if (!visible->connection_info_initialized) {
    return engine::PageSecurity::kNone;
  }
  if (level == security_state::SECURE) {
    return engine::PageSecurity::kSecure;
  }
  if (visible->ran_mixed_content || visible->displayed_mixed_content || visible->contained_mixed_form ||
      visible->ran_content_with_cert_errors || visible->displayed_content_with_cert_errors) {
    return engine::PageSecurity::kMixedContent;
  }
  if (level == security_state::DANGEROUS) {
    return engine::PageSecurity::kDangerous;
  }
  // A cryptographic scheme the engine still warns about, such as legacy TLS.
  return engine::PageSecurity::kInsecure;
}

bool EnginePage::ShowsInitialBlank(const GURL& url) const {
  return url.IsAboutBlank() && pending_url_ && *pending_url_ != url.spec();
}

void EnginePage::Report(engine::EngineEvent event) {
  if (!standalone_) {
    binding_->Report(std::move(event));
  }
}

void EnginePage::Present(engine::EnginePresentation presentation) {
  binding_->Present(std::move(presentation));
}

// What the platform asks of the page directly.

bool EnginePage::GoToOffset(int offset) {
  if (!web_contents() || offset == 0) {
    return false;
  }
  auto& controller = web_contents()->GetController();
  if (!controller.CanGoToOffset(offset)) {
    return false;
  }
  controller.GoToOffset(offset);
  return true;
}

bool EnginePage::Reload(bool bypasses_cache) {
  if (!web_contents()) {
    return false;
  }
  web_contents()->GetController().Reload(
      bypasses_cache ? content::ReloadType::BYPASSING_CACHE : content::ReloadType::NORMAL, true);
  return true;
}

bool EnginePage::StopLoading() {
  if (!web_contents()) {
    return false;
  }
  web_contents()->Stop();
  return true;
}

bool EnginePage::Zoom(double factor) {
  if (!std::isfinite(factor) || factor < kMinimumZoom || factor > kMaximumZoom) {
    return false;
  }
  zoom_ = factor;
  ApplyZoom();
  return true;
}

void EnginePage::ApplyZoom() {
  if (!zoom_ || !web_contents()) {
    return;
  }
  auto* zoom = zoom::ZoomController::FromWebContents(web_contents());
  if (!zoom) {
    return;
  }
  zoom->SetZoomMode(zoom::ZoomController::ZOOM_MODE_ISOLATED);
  zoom->SetZoomLevel(blink::ZoomFactorToZoomLevel(*zoom_));
}

bool EnginePage::Find(const std::string& query, bool backwards, bool case_sensitive) {
  if (!find_helper_) {
    return false;
  }
  if (query.empty()) {
    find_pending_ = false;
    find_helper_->StopFinding(find_in_page::SelectionAction::kClear);
    Present(engine::FindFinished{.page_id = id_});
    return true;
  }
  find_pending_ = true;
  find_helper_->StartFinding(base::UTF8ToUTF16(query), !backwards, case_sensitive, true);
  return true;
}

// The final update of a search carries its total and the ordinal of the
// match it selected; earlier updates are still counting.
void EnginePage::OnFindResultAvailable(content::WebContents*) {
  if (!find_helper_ || !find_pending_ || !find_helper_->find_result().final_update()) {
    return;
  }
  find_pending_ = false;
  const auto& result = find_helper_->find_result();
  Present(engine::FindFinished{.page_id = id_,
                               .matches = std::max(0, result.number_of_matches()),
                               .active_match = std::max(0, result.active_match_ordinal())});
}

void EnginePage::OnFindTabHelperDestroyed(find_in_page::FindTabHelper*) {
  find_helper_ = nullptr;
  find_pending_ = false;
}

bool EnginePage::Capture(const engine::Guid& capture_id,
                         const std::optional<engine::PageArea>& area,
                         double width) {
  auto* view = web_contents() ? web_contents()->GetRenderWidgetHostView() : nullptr;
  if (!view || !std::isfinite(width) || width < 0 || width > kMaximumCaptureWidth) {
    return false;
  }
  gfx::Rect bounds;
  if (area) {
    if (!std::isfinite(area->x) || !std::isfinite(area->y) || !std::isfinite(area->width) ||
        !std::isfinite(area->height)) {
      return false;
    }
    bounds = gfx::Rect(static_cast<int>(area->x), static_cast<int>(area->y), static_cast<int>(area->width),
                       static_cast<int>(area->height));
    bounds.Intersect(gfx::Rect(view->GetViewBounds().size()));
    if (bounds.IsEmpty()) {
      return false;
    }
  }
  const gfx::Size size = bounds.IsEmpty() ? view->GetViewBounds().size() : bounds.size();
  if (size.IsEmpty()) {
    return false;
  }
  gfx::Size output;
  if (width > 0) {
    output = gfx::Size(std::max(1, static_cast<int>(width)),
                       std::max(1, static_cast<int>(width * size.height() / size.width())));
  }
  view->CopyFromSurface(
      bounds, output, kCaptureTimeout,
      base::BindOnce(
          [](base::WeakPtr<EnginePage> page, engine::Guid capture_id, const content::CopyFromSurfaceResult& result) {
            if (!page) {
              return;
            }
            std::optional<std::vector<uint8_t>> png;
            if (result.has_value() && !result->bitmap.drawsNothing()) {
              png = gfx::PNGCodec::EncodeBGRASkBitmap(result->bitmap, false);
            }
            page->Present(engine::PageCaptured{.page_id = page->id_, .capture_id = capture_id, .png = std::move(png)});
          },
          weak_factory_.GetWeakPtr(), capture_id));
  return true;
}

bool EnginePage::Export(const engine::Guid& export_id, engine::PageExportFormat format, double width) {
  if (!web_contents()) {
    return false;
  }
  if (!documents_) {
    documents_ = std::make_unique<PageDocuments>(web_contents());
  }
  documents_->Export(
      format, width,
      base::BindOnce(
          [](base::WeakPtr<EnginePage> page, engine::Guid export_id, std::optional<std::vector<uint8_t>> document,
             std::optional<engine::PageExportFailure> failure) {
            if (!page) {
              return;
            }
            page->Present(engine::PageExported{
                .page_id = page->id_, .export_id = export_id, .document = std::move(document), .failure = failure});
          },
          weak_factory_.GetWeakPtr(), export_id));
  return true;
}

bool EnginePage::Show() {
  if (!web_contents()) {
    return false;
  }
  web_contents()->WasShown();
  web_contents()->Focus();
  StateChanged();
  return true;
}

bool EnginePage::Hide() {
  if (!web_contents()) {
    return false;
  }
  web_contents()->WasHidden();
  StateChanged();
  return true;
}

}  // namespace crest

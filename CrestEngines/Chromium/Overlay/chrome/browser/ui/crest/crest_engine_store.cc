#include "chrome/browser/ui/crest/crest_engine_store.h"

#include <algorithm>
#include <string_view>
#include <utility>
#include <vector>

#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/memory/ref_counted_memory.h"
#include "base/strings/escape.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/thread_pool.h"
#include "base/uuid.h"
#include "base/values.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_profiles.h"
#include "chrome/browser/ui/crest/crest_engine_prompts.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "components/crx_file/id_util.h"
#include "components/update_client/update_query_params.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/storage_partition.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/crx_installer.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_util.h"
#include "extensions/browser/install/crx_install_error.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_urls.h"
#include "net/base/load_flags.h"
#include "net/base/net_errors.h"
#include "net/cookies/site_for_cookies.h"
#include "net/http/http_status_code.h"
#include "net/http/http_response_headers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"
#include "url/url_constants.h"

namespace crest {

namespace {

bool IsWebStoreURL(const GURL& url) {
  return url.SchemeIs(url::kHttpsScheme) && url.host() == "chromewebstore.google.com";
}

// Chrome Web Store identifiers are 32 characters from a-p.
bool IsExtensionID(std::string_view candidate) {
  if (candidate.size() != 32) return false;
  for (char character : candidate)
    if (character < 'a' || character > 'p') return false;
  return true;
}

// The extension a store listing URL names, or an empty string for any other
// store page. A listing is /detail/<id> or /detail/<name>/<id>, and its
// reviews and support pages add a segment after the identifier.
std::string WebStoreExtensionID(const GURL& url) {
  if (!IsWebStoreURL(url)) return std::string();
  const std::string_view path = url.path();
  std::vector<std::string_view> parts = base::SplitStringPiece(
      path, "/", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY);
  if (parts.size() < 2 || parts.front() != "detail") return std::string();
  if (parts.size() > 2 && IsExtensionID(parts[2])) return std::string(parts[2]);
  if (IsExtensionID(parts[1])) return std::string(parts[1]);
  return std::string();
}

// The isolated-world script. It uses DOM and CSSOM APIs only: the store's
// content policy rejects stylesheets and inline style attributes Crest would
// add to the markup, but script-driven property changes are not markup.
const char* CrestStoreScript() {
  return R"JS((function() {
  if (window.__crestStore) { window.__crestStore.render(); return; }
  var labels = { install: 'Add to Crest', installed: 'Added to Crest',
                 remove: 'Remove from Crest', busy: 'Installing…' };
  var state = { id: '', installed: false, busy: false };
  var adopted = null, hovering = false, pending = false;
  // The host's listing rule: /detail/<id> or /detail/<name>/<id>, optionally
  // followed by the listing's reviews or support page.
  function detailID() {
    var match = /^\/detail\/(?:[^\/]+\/)?([a-p]{32})(?:\/|$)/.exec(location.pathname);
    return match ? match[1] : '';
  }
  function label(button) { return button.querySelector('span[jsname="V67aGc"]') || button; }
  function text(node) { return (node.textContent || '').replace(/\s+/g, ' ').trim(); }
  // The store keeps the listing it navigated away from in the document and
  // only hides it, so anything that is not actually rendered is stale.
  function shown(element) {
    if (!element || !element.isConnected) return false;
    var rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }
  // The store words its button in the page's language, and some languages
  // leave Chrome out of it, so the button is known by what the store does
  // with it: it is the labelled control the store disables for a browser that
  // is not Chrome, or the one that names Chrome or, once adopted, Crest.
  function installButton(button) {
    var value = text(label(button));
    return value !== '' && (button.disabled || /chrome|crest/i.test(value));
  }
  // The listing's own install button: the one in the section that carries the
  // extension's title, so a related listing's button is never adopted.
  function locate() {
    if (shown(adopted)) return adopted;
    adopted = null; hovering = false;
    if (!detailID()) return null;
    var headings = document.querySelectorAll('h1'), scope = null;
    for (var heading = 0; heading < headings.length; heading++) {
      if (!shown(headings[heading])) continue;
      scope = headings[heading].closest('section');
      break;
    }
    if (!scope) return null;
    var buttons = scope.querySelectorAll('button');
    for (var index = 0; index < buttons.length; index++) {
      var button = buttons[index];
      if (!shown(button) || !installButton(button)) continue;
      adopted = button;
      button.addEventListener('pointerenter', function() { hovering = true; render(); });
      button.addEventListener('pointerleave', function() { hovering = false; render(); });
      button.addEventListener('focus', function() { hovering = true; render(); });
      button.addEventListener('blur', function() { hovering = false; render(); });
      return button;
    }
    return null;
  }
  // The store's desktop layout keeps a minimum width wider than a Crest page
  // card, which pushes the listing and its install button past the card's
  // edge. Releasing that minimum lets the store use its own narrow layout.
  function relax() {
    // The store keeps the listing it navigated away from, so each document can
    // hold more than one of these; every one of them has to be released.
    var elements = [document.body].concat(
        Array.prototype.slice.call(document.querySelectorAll('header, main')));
    for (var index = 0; index < elements.length; index++) {
      var element = elements[index];
      if (!element) continue;
      var minimum = parseFloat(getComputedStyle(element).minWidth);
      if (minimum > 0 && minimum > window.innerWidth) element.style.minWidth = 'auto';
    }
  }
  // Crest installs extensions itself, so the store's prompts to switch to
  // Chrome are noise. Their wording follows the page's language, so each is
  // found from the action it offers: the dialog links to Chrome's download
  // page, and the listing's notice holds the store's Install Chrome button,
  // which the store's own analytics name 276336.
  var promptActions = '[role="dialog"] a[href^="https://www.google.com/chrome/"], ' +
                      'button[jslog^="276336;"]';
  // The outermost element around a notice's action that holds no other
  // control and no heading, so the listing around it is never affected.
  function notice(action) {
    var box = action;
    for (var parent = box.parentElement; parent && parent !== document.body;
         parent = parent.parentElement) {
      if (parent.querySelector('h1, h2, h3') ||
          parent.querySelectorAll('a[href], button').length > 1) break;
      box = parent;
    }
    return box;
  }
  function hidePrompts() {
    var actions = document.querySelectorAll(promptActions);
    for (var index = 0; index < actions.length; index++) {
      var box = actions[index].closest('[role="dialog"]') || notice(actions[index]);
      if (box.style.display !== 'none') box.style.display = 'none';
    }
  }
  function render() {
    relax();
    hidePrompts();
    var button = locate();
    if (!button) return;
    var wanted = state.busy ? labels.busy
        : (state.installed ? (hovering ? labels.remove : labels.installed) : labels.install);
    var span = label(button);
    if (text(span) !== wanted) span.textContent = wanted;
    if (button.disabled) button.disabled = false;
    button.removeAttribute('disabled');
    button.setAttribute('aria-disabled', state.busy ? 'true' : 'false');
    button.setAttribute('aria-label', wanted);
    // The labels are Crest's English, whatever the store's language, so
    // assistive technology reads them as English and a right-to-left page
    // keeps the progress label's ellipsis at its end.
    if (button.lang !== 'en') button.lang = 'en';
    if (button.dir !== 'ltr') button.dir = 'ltr';
  }
  function schedule() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function() { pending = false; render(); });
  }
  // The core owns the install review, so the click never reaches the store's
  // own handler. The request names the extension the page itself is showing
  // and the core checks that name again before it downloads anything.
  function request() {
    var id = detailID();
    if (!id || state.busy) return;
    var command = state.installed ? 'crest-remove' : 'crest-install';
    if (!state.installed) { state.busy = true; render(); }
    history.replaceState(history.state, '',
        location.pathname + location.search + '#' + command + '=' + id);
  }
  document.addEventListener('click', function(event) {
    var button = locate();
    var target = event.target;
    if (!button || !target || !(target === button || (target.nodeType === 1 && button.contains(target)))) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    request();
  }, true);
  window.addEventListener('resize', function() { schedule(); });
  new MutationObserver(schedule).observe(document.documentElement,
      { childList: true, subtree: true, characterData: true });
  window.__crestStore = {
    render: render,
    apply: function(next) {
      state.id = next && typeof next.id === 'string' ? next.id : '';
      state.installed = !!(next && next.installed);
      state.busy = false;
      if (!adopted || !adopted.isConnected) { adopted = null; }
      render();
    }
  };
  render();
})();)JS";
}

}  // namespace

PageStore::PageStore(content::WebContents* contents, const engine::Guid& page, Present present)
    : contents_(contents), page_(page), present_(std::move(present)) {}

PageStore::~PageStore() = default;

void PageStore::DocumentAvailable() {
  if (!Frame()) {
    return;
  }
  Run(CrestStoreScript());
  Refresh();
}

bool PageStore::Committed(const GURL& url) {
  if (Consume(url)) {
    return true;
  }
  // The store is a single-page application: a listing change keeps the
  // document, so the script stays and only its state has to be refreshed.
  // Restoring the listing's own address is Crest's own edit, not a change of
  // listing, so it must not reset a request that is still open.
  if (request_open_) {
    request_open_ = false;
  } else {
    Refresh();
  }
  return false;
}

void PageStore::RequestFinished() {
  request_open_ = false;
  Refresh();
}

void PageStore::Refresh() {
  auto* frame = Frame();
  if (!frame) {
    return;
  }
  const std::string id = WebStoreExtensionID(frame->GetLastCommittedURL());
  bool installed = false;
  if (!id.empty()) {
    auto* registry = extensions::ExtensionRegistry::Get(contents_->GetBrowserContext());
    installed = registry && registry->GetInstalledExtension(id) != nullptr;
  }
  auto json = base::WriteJson(base::DictValue().Set("id", id).Set("installed", installed));
  if (!json) {
    return;
  }
  Run("window.__crestStore && window.__crestStore.apply(" + *json + ");");
}

// Regular profiles only: a private window must not change a Space's
// persistent extension state, so its store pages keep the engine's own
// behaviour.
content::RenderFrameHost* PageStore::Frame() const {
  if (contents_->GetBrowserContext()->IsOffTheRecord()) {
    return nullptr;
  }
  auto* frame = contents_->GetPrimaryMainFrame();
  if (!frame || !IsWebStoreURL(frame->GetLastCommittedURL())) {
    return nullptr;
  }
  return frame;
}

void PageStore::Run(const std::string& script) {
  if (auto* frame = Frame()) {
    frame->ExecuteJavaScriptInIsolatedWorld(base::UTF8ToUTF16(script), {}, ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
}

// A request the injected script wrote into the listing's own URL fragment.
// The extension it names has to be the one the page is showing, so a store
// page cannot ask Crest to install anything else, and Crest still runs its
// own install review before the engine verifies the package.
bool PageStore::Consume(const GURL& url) {
  if (!Frame() || !url.has_ref()) {
    return false;
  }
  const std::string_view ref = url.ref();
  constexpr std::string_view kInstall = "crest-install=";
  constexpr std::string_view kRemove = "crest-remove=";
  bool removes = false;
  std::string requested;
  if (base::StartsWith(ref, kInstall)) {
    requested = std::string(ref.substr(kInstall.size()));
  } else if (base::StartsWith(ref, kRemove)) {
    removes = true;
    requested = std::string(ref.substr(kRemove.size()));
  } else {
    return false;
  }
  // Leave the listing's own address in place; the fragment is a message.
  Run("history.replaceState(history.state, '', location.pathname + location.search);");
  const std::string expected = WebStoreExtensionID(url);
  if (expected.empty() || requested != expected) {
    Refresh();
    return true;
  }
  // Crest owns the request now: the button keeps its own progress label
  // until the review Crest presents finishes.
  request_open_ = true;
  if (removes) {
    present_.Run(engine::StoreRemovalRequested{.page_id = page_, .extension_id = expected});
  } else {
    present_.Run(engine::StoreInstallRequested{.page_id = page_, .extension_id = expected});
  }
  return true;
}

namespace {

constexpr net::NetworkTrafficAnnotationTag kWebStoreDownloadAnnotation =
    net::DefineNetworkTrafficAnnotation("crest_web_store_download", R"(
      semantics {
        sender: "Crest Web Store install"
        description: "Downloads a Chrome Web Store extension package for installation."
        trigger: "The person installs an extension from a Chrome Web Store listing."
        data: "The extension's ID and Chromium's version, platform and language, and the Space's cookies when the service refuses the request without them."
        destination: GOOGLE_OWNED_SERVICE
      }
      policy {
        cookies_allowed: YES
        cookies_store: "user"
        setting: "Only runs when the person installs an extension. Cookies are sent only when the service refuses the request without them, as it does for a private or trusted-tester item."
      })");

// The package of `extension_id` from Google's update service, as Chromium's
// Web Store installer asks for it.
GURL PackageURL(const std::string& extension_id) {
  return GURL(extension_urls::GetWebstoreUpdateUrl().spec() + "?response=redirect&" +
              update_client::UpdateQueryParams::Get(update_client::UpdateQueryParams::CRX) + "&x=" +
              base::EscapeQueryParamValue("id=" + extension_id + "&installsource=ondemand&uc", true));
}

// Whether a request the service refused with `status` may ask again with the
// profile's cookies: only Google's own service over HTTPS, which answers 401
// or 403 for an item the request's account can't see.
bool MayAskWithCookies(const GURL& url, int status) {
  return (status == net::HTTP_UNAUTHORIZED || status == net::HTTP_FORBIDDEN) &&
         url.SchemeIs(url::kHttpsScheme) && url.DomainIs("google.com");
}

// A copy of `package` for one profile's install, which CrxInstaller deletes
// once it is done, or an empty path when none could be made.
base::FilePath StagedCopy(const base::FilePath& package) {
  base::FilePath directory;
  if (!base::GetTempDir(&directory)) {
    return base::FilePath();
  }
  const base::FilePath staged =
      directory.AppendASCII("crest-extension-" + base::Uuid::GenerateRandomV4().AsLowercaseString() + ".crx");
  return base::CopyFile(package, staged) ? staged : base::FilePath();
}

// The question the core asks about the package `prompt` describes, in the
// engine's own words.
engine::ExtensionInstallQuestion QuestionFor(const extensions::InstallPromptData& prompt) {
  const extensions::Extension& extension = *prompt.extension();
  engine::ExtensionInstallQuestion question{
      .extension_id = extension.id(),
      .name = extension.name(),
      .version = extension.version().GetString(),
      .can_withhold_site_access = extensions::util::CanWithholdPermissionsFromExtension(extension),
      .withholds_site_access = prompt.ShouldWithheldPermissionsOnDialogAccept()};
  if (const std::string* summary = extension.manifest()->FindStringPath("description")) {
    question.summary = *summary;
  }
  const auto details = prompt.GetPermissions();
  for (size_t index = 0; index < prompt.GetPermissionCount(); ++index) {
    question.permissions.push_back(base::UTF16ToUTF8(prompt.GetPermission(index)));
    if (index < details.details.size() && !details.details[index].empty()) {
      question.permissions.push_back(base::UTF16ToUTF8(details.details[index]));
    }
  }
  if (!prompt.icon().IsEmpty()) {
    if (auto png = prompt.icon().As1xPNGBytes(); png && png->size()) {
      question.icon = engine::Bytes(png->data(), png->data() + png->size());
    }
  }
  return question;
}

// Asks the core whether install `install` may install the package `prompt`
// describes. The core answers from the person's review or from the consent
// they gave the same package, and the installer hears the answer.
void AskCore(const engine::Guid& install,
             std::unique_ptr<ExtensionInstallPromptShowParams>,
             ExtensionInstallPrompt::DoneCallback done,
             std::unique_ptr<extensions::InstallPromptData> prompt) {
  using Result = extensions::ExtensionInstallPromptClient::Result;
  using Payload = ExtensionInstallPrompt::DoneCallbackPayload;
  EngineBinding& binding = EngineBinding::Get();
  if (binding.disposing() || !prompt->extension() || prompt->requires_parent_permission()) {
    std::move(done).Run(Payload(Result::ABORTED));
    return;
  }
  engine::ExtensionInstallQuestion question = QuestionFor(*prompt);
  binding.Prompts().AskToInstall(
      install, std::move(question),
      base::BindOnce(
          [](ExtensionInstallPrompt::DoneCallback done, std::unique_ptr<extensions::InstallPromptData> prompt,
             bool accepted, bool withholds) {
            if (!accepted) {
              prompt->OnDialogCanceled();
              std::move(done).Run(Payload(Result::USER_CANCELED));
              return;
            }
            prompt->OnDialogAccepted();
            std::move(done).Run(
                Payload(withholds ? Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS : Result::ACCEPTED));
          },
          std::move(done), std::move(prompt)));
}

// The prompt each of the core's installs installs with. Its question goes to
// the core, never to a window: the person's review is Crest's, in whichever
// window shows it.
class CorePrompt final : public ExtensionInstallPrompt {
 public:
  CorePrompt(Profile* profile, const engine::Guid& install)
      : ExtensionInstallPrompt(
            profile,
            gfx::NativeWindow(),
            std::make_unique<extensions::InstallPromptData>(extensions::InstallPromptData::INSTALL_PROMPT)),
        install_(install) {}

  // CrxInstaller asks to confirm the install once it verified the package.
  void ConfirmInstall(DoneCallback done, const extensions::Extension* extension) override {
    ShowDialog(std::move(done), extension, nullptr, base::BindRepeating(&AskCore, install_));
  }

 private:
  const engine::Guid install_;
};

}  // namespace

// WebStoreDownload.

WebStoreDownload::WebStoreDownload(Profile* profile, const std::string& extension_id, Progress progress, Done done)
    : factory_(profile->GetDefaultStoragePartition()->GetURLLoaderFactoryForBrowserProcess()),
      url_(PackageURL(extension_id)),
      progress_(std::move(progress)),
      done_(std::move(done)) {
  Begin(/*with_cookies=*/false);
}

WebStoreDownload::~WebStoreDownload() = default;

void WebStoreDownload::Begin(bool with_cookies) {
  with_cookies_ = with_cookies;
  length_ = -1;
  auto request = std::make_unique<network::ResourceRequest>();
  request->url = url_;
  if (with_cookies) {
    // As Chromium's extension downloader asks for an item that needs an
    // account: the cookies of the service's own site, never from a cache.
    request->credentials_mode = network::mojom::CredentialsMode::kInclude;
    request->site_for_cookies = net::SiteForCookies::FromUrl(url_);
    request->load_flags = net::LOAD_DISABLE_CACHE;
  } else {
    request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  }
  // Someone is waiting on this download, as on Chromium's own foreground
  // extension fetches. At the default idle priority the loader writes the
  // package on best-effort tasks, which Chromium holds until it counts
  // startup as complete: up to three minutes when no page has loaded.
  request->priority = net::MEDIUM;
  loader_ = network::SimpleURLLoader::Create(std::move(request), kWebStoreDownloadAnnotation);
  loader_->SetOnResponseStartedCallback(base::BindOnce(&WebStoreDownload::Started, base::Unretained(this)));
  loader_->SetOnDownloadProgressCallback(base::BindRepeating(&WebStoreDownload::Progressed, base::Unretained(this)));
  loader_->DownloadToTempFile(factory_.get(), base::BindOnce(&WebStoreDownload::Finished, base::Unretained(this)));
}

// Only a package's size counts toward progress, never a refusal's body.
void WebStoreDownload::Started(const GURL&, const network::mojom::URLResponseHead& head) {
  length_ = head.headers && head.headers->response_code() == net::HTTP_OK ? head.content_length : -1;
}

void WebStoreDownload::Progressed(uint64_t received) {
  if (length_ > 0) {
    progress_.Run(std::min(1.0, static_cast<double>(received) / static_cast<double>(length_)));
  }
}

void WebStoreDownload::Finished(base::FilePath path) {
  const network::mojom::URLResponseHead* head = loader_->ResponseInfo();
  const int status = head && head->headers ? head->headers->response_code() : 0;
  if (!path.empty() && status == net::HTTP_OK) {
    std::move(done_).Run(std::move(path));
    return;
  }
  // A successful status other than 200 carries no package: the service
  // answers 204 for an extension it will not serve to this browser.
  if (!path.empty()) {
    base::ThreadPool::PostTask(FROM_HERE, {base::MayBlock()}, base::GetDeleteFileCallback(path));
  }
  // A private or trusted-tester item is served only to an account that can
  // see it. Replacing the loader inside its own callback is allowed.
  if (!with_cookies_ && MayAskWithCookies(url_, status)) {
    Begin(/*with_cookies=*/true);
    return;
  }
  LOG(WARNING) << "Crest could not download an extension package: "
               << (status ? "HTTP " + base::NumberToString(status) : net::ErrorToString(loader_->NetError()));
  std::move(done_).Run(std::nullopt);
}

// ExtensionInstalls.

// One install: the extension it installs, its download while it runs, and
// the package it keeps once downloaded, which each profile's install copies.
struct ExtensionInstalls::Running {
  std::string extension_id;
  std::unique_ptr<WebStoreDownload> download;
  base::FilePath package;
};

ExtensionInstalls::ExtensionInstalls(EngineBinding& binding) : binding_(binding) {}

ExtensionInstalls::~ExtensionInstalls() {
  for (const auto& [install, running] : installs_) {
    if (!running->package.empty()) {
      base::ThreadPool::PostTask(FROM_HERE, {base::MayBlock()}, base::GetDeleteFileCallback(running->package));
    }
  }
}

ExtensionInstalls::Running* ExtensionInstalls::Find(const engine::Guid& install) {
  const auto found = installs_.find(install);
  return found == installs_.end() ? nullptr : found->second.get();
}

// The package comes through the profile of the install's first Space, which
// loads for it when nothing has.
void ExtensionInstalls::Download(const engine::DownloadExtension& command) {
  if (installs_.contains(command.install_id)) {
    return;
  }
  auto running = std::make_unique<Running>();
  running->extension_id = command.extension_id;
  installs_[command.install_id] = std::move(running);
  binding_->Profiles().Prepare(GuidText(command.profile_id),
                               base::BindOnce(&ExtensionInstalls::StartDownload, weak_factory_.GetWeakPtr(),
                                              command.install_id, command.profile_id));
}

void ExtensionInstalls::StartDownload(const engine::Guid& install, const engine::Guid& profile_id, bool ready) {
  Running* running = Find(install);
  if (!running) {
    return;
  }
  Profile* profile = ready ? binding_->Profiles().Find(GuidText(profile_id)) : nullptr;
  if (!profile || profile->IsOffTheRecord()) {
    Fail(install, profile_id, engine::ExtensionInstallFailure::kSpaceUnavailable);
    return;
  }
  if (!crx_file::id_util::IdIsValid(running->extension_id)) {
    Fail(install, profile_id, engine::ExtensionInstallFailure::kRefused);
    return;
  }
  running->download = std::make_unique<WebStoreDownload>(
      profile, running->extension_id,
      base::BindRepeating(&ExtensionInstalls::Progressed, weak_factory_.GetWeakPtr(), install),
      base::BindOnce(&ExtensionInstalls::Downloaded, weak_factory_.GetWeakPtr(), install, profile_id));
}

void ExtensionInstalls::Progressed(const engine::Guid& install, double fraction) {
  binding_->Present(engine::ExtensionDownloadProgressed{.install_id = install, .fraction = fraction});
}

void ExtensionInstalls::Downloaded(const engine::Guid& install,
                                   const engine::Guid& profile,
                                   std::optional<base::FilePath> package) {
  Running* running = Find(install);
  if (!running) {
    if (package) {
      base::ThreadPool::PostTask(FROM_HERE, {base::MayBlock()}, base::GetDeleteFileCallback(*package));
    }
    return;
  }
  if (!package) {
    Fail(install, profile, engine::ExtensionInstallFailure::kDownloadFailed);
    return;
  }
  running->package = std::move(*package);
  binding_->Report(engine::ExtensionDownloaded{.install_id = install});
}

void ExtensionInstalls::Install(const engine::InstallExtensionPackage& command) {
  binding_->Profiles().Prepare(GuidText(command.profile_id),
                               base::BindOnce(&ExtensionInstalls::StagePackage, weak_factory_.GetWeakPtr(),
                                              command.install_id, command.profile_id));
}

// Each profile installs its own copy of the package, so every one of them
// verifies its signature and publisher proof and keeps its own data.
void ExtensionInstalls::StagePackage(const engine::Guid& install, const engine::Guid& profile_id, bool ready) {
  Running* running = Find(install);
  if (!running) {
    return;
  }
  Profile* profile = ready ? binding_->Profiles().Find(GuidText(profile_id)) : nullptr;
  if (!profile || profile->IsOffTheRecord()) {
    Fail(install, profile_id, engine::ExtensionInstallFailure::kSpaceUnavailable);
    return;
  }
  if (running->package.empty()) {
    Fail(install, profile_id, engine::ExtensionInstallFailure::kRefused);
    return;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&StagedCopy, running->package),
      base::BindOnce(&ExtensionInstalls::Staged, weak_factory_.GetWeakPtr(), install, profile_id));
}

void ExtensionInstalls::Staged(const engine::Guid& install, const engine::Guid& profile_id, base::FilePath staged) {
  Profile* profile = Find(install) ? binding_->Profiles().Find(GuidText(profile_id)) : nullptr;
  if (!profile || staged.empty()) {
    if (!staged.empty()) {
      base::ThreadPool::PostTask(FROM_HERE, {base::MayBlock()}, base::GetDeleteFileCallback(staged));
    }
    if (Find(install)) {
      Fail(install, profile_id,
           profile ? engine::ExtensionInstallFailure::kRefused : engine::ExtensionInstallFailure::kSpaceUnavailable);
    }
    return;
  }
  auto prompt = std::make_unique<CorePrompt>(profile, install);
  prompt->SetSkipPostInstallUI(true);
  auto installer = extensions::CrxInstaller::Create(profile, std::move(prompt));
  installer->set_expected_id(Find(install)->extension_id);
  installer->set_is_gallery_install(true);
  installer->set_delete_source(true);
  installer->AddInstallerCallback(
      base::BindOnce(&ExtensionInstalls::Installed, weak_factory_.GetWeakPtr(), install, profile_id));
  installer->InstallCrx(staged);
}

void ExtensionInstalls::Installed(const engine::Guid& install,
                                  const engine::Guid& profile,
                                  const std::optional<extensions::CrxInstallError>& error) {
  if (!Find(install)) {
    return;
  }
  if (!error) {
    binding_->Report(engine::ExtensionInstalled{.install_id = install, .profile_id = profile});
    return;
  }
  const auto detail = error->detail();
  LOG(WARNING) << "Crest could not install an extension package: " << base::UTF16ToUTF8(error->message());
  Fail(install, profile,
       detail == extensions::CrxInstallErrorDetail::USER_CANCELED ||
               detail == extensions::CrxInstallErrorDetail::USER_ABORTED
           ? engine::ExtensionInstallFailure::kCanceled
           : engine::ExtensionInstallFailure::kRefused);
}

void ExtensionInstalls::Fail(const engine::Guid& install,
                             const engine::Guid& profile,
                             engine::ExtensionInstallFailure reason) {
  binding_->Report(engine::ExtensionInstallFailed{.install_id = install, .profile_id = profile, .reason = reason});
}

// The core is done with the install: a download still running stops, and the
// package goes.
void ExtensionInstalls::End(const engine::EndExtensionInstall& command) {
  const auto found = installs_.find(command.install_id);
  if (found == installs_.end()) {
    return;
  }
  if (!found->second->package.empty()) {
    base::ThreadPool::PostTask(FROM_HERE, {base::MayBlock()}, base::GetDeleteFileCallback(found->second->package));
  }
  installs_.erase(found);
}

}  // namespace crest

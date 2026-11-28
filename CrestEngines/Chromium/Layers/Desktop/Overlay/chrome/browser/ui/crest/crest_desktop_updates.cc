#include "chrome/browser/ui/crest/crest_desktop_updates.h"

#include <utility>

#include "base/base64.h"
#include "base/command_line.h"
#include "base/files/file.h"
#include "base/files/file_util.h"
#include "base/files/memory_mapped_file.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/path_service.h"
#include "base/process/launch.h"
#include "base/strings/string_util.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/ui/crest/crest_desktop_host.h"
#include "crypto/keypair.h"
#include "crypto/sign.h"
#include "net/base/load_flags.h"
#include "net/base/url_util.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "net/url_request/redirect_info.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "url/url_constants.h"

namespace crest {

namespace {

constexpr net::NetworkTrafficAnnotationTag kUpdateAnnotation =
    net::DefineNetworkTrafficAnnotation("crest_software_update", R"(
      semantics {
        sender: "Crest software updates"
        description: "Reads the update feed of the channel an installed Crest follows, and downloads the update the person or the scheduled check chose, as the Mac app's Sparkle does."
        trigger: "Every hour while an installed Crest runs, when the person checks for updates in Settings, and when an update installs."
        data: "Nothing beyond the request for the feed or the installer."
        destination: OTHER
      }
      policy {
        cookies_allowed: NO
        setting: "Check for updates automatically, in Settings > About."
      })");

// A feed lists a few releases; an installer carries the whole app.
constexpr size_t kMaximumFeedBytes = 4 * 1024 * 1024;
constexpr int64_t kMaximumInstallerBytes = int64_t{1} << 30;
constexpr base::TimeDelta kFeedTimeout = base::Minutes(1);

// What a silent update tells Setup (CrestDesktop/installer/Crest.iss): show
// nothing, wait for Crest to quit, and open it again once installed.
constexpr const char* kInstallerArguments[] = {
    "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/update=1", "/relaunch=1",
};

// Where an update may come from: https, or this device, where a local build
// serves its own feed. Every installer is checked against the key either way.
bool AllowsUpdateURL(const GURL& url) {
  return url.is_valid() && (url.SchemeIs(url::kHttpsScheme) || (url.SchemeIs(url::kHttpScheme) && net::IsLocalhost(url)));
}

// A feed's name, as the interface asks for one: appcast[-…].xml.
bool IsFeedName(const std::string& name) {
  if (!base::StartsWith(name, "appcast") || !base::EndsWith(name, ".xml")) return false;
  for (char character : name) {
    if (!base::IsAsciiLower(character) && !base::IsAsciiDigit(character) && character != '-' && character != '.') {
      return false;
    }
  }
  return name.find("..") == std::string::npos;
}

base::FilePath InstalledFolder() {
  return base::PathService::CheckedGet(base::DIR_EXE);
}

std::optional<DesktopUpdates::Settings> ReadSettingsFile(const base::FilePath& file) {
  std::string text;
  if (!base::ReadFileToStringWithMaxSize(file, &text, 64 * 1024)) return std::nullopt;
  std::optional<base::DictValue> fields = base::JSONReader::ReadDict(text, base::JSON_PARSE_RFC);
  if (!fields) return std::nullopt;
  const std::string* version = fields->FindString("version");
  const std::optional<double> build = fields->FindDouble("build");
  const std::string* channel = fields->FindString("channel");
  const std::string* feed_base = fields->FindString("feedBase");
  const std::string* public_key = fields->FindString("publicKey");
  if (!version || !build || !channel || !feed_base || !public_key || *build < 0 || *build > (int64_t{1} << 52)) {
    return std::nullopt;
  }
  DesktopUpdates::Settings settings;
  settings.version = *version;
  settings.build = static_cast<int64_t>(*build);
  settings.channel = *channel;
  settings.feed_base = GURL(*feed_base);
  if (!AllowsUpdateURL(settings.feed_base) || !base::EndsWith(settings.feed_base.path(), "/")) return std::nullopt;
  std::optional<std::vector<uint8_t>> key = base::Base64Decode(*public_key);
  if (!key || key->size() != settings.public_key.size()) return std::nullopt;
  std::copy(key->begin(), key->end(), settings.public_key.begin());
  return settings;
}

// Empties the folder an update downloads into, beside the installed app,
// and answers where the installer goes, or nothing.
base::FilePath PrepareDownload() {
  const base::FilePath folder = InstalledFolder().DirName().Append(FILE_PATH_LITERAL("Update"));
  base::DeletePathRecursively(folder);
  if (!base::CreateDirectory(folder)) return base::FilePath();
  return folder.Append(FILE_PATH_LITERAL("Crest-Setup.exe"));
}

// Checks the installer and runs it. The file stays open, and no one may
// write it, from the check until the installer has started.
DesktopUpdates::Outcome CheckAndRun(const base::FilePath& installer,
                                    int64_t length,
                                    const std::vector<uint8_t>& signature,
                                    const std::array<uint8_t, 32>& public_key) {
  using Outcome = DesktopUpdates::Outcome;
  base::File file(installer, base::File::FLAG_OPEN | base::File::FLAG_READ | base::File::FLAG_WIN_EXCLUSIVE_WRITE);
  if (!file.IsValid()) return Outcome::kDownload;
  if (file.GetLength() != length) {
    file.Close();
    base::DeleteFile(installer);
    return Outcome::kLength;
  }
  {
    base::MemoryMappedFile mapped;
    if (!mapped.Initialize(std::move(file))) return Outcome::kDownload;
    if (signature.size() == 64 &&
        crypto::sign::Verify(crypto::sign::SignatureKind::ED25519,
                             crypto::keypair::PublicKey::FromEd25519PublicKey(public_key), mapped.bytes(),
                             signature)) {
      base::CommandLine command(installer);
      for (const char* argument : kInstallerArguments) command.AppendArg(argument);
      base::LaunchOptions options;
      options.current_directory = installer.DirName();
      // Setup outlives Crest, which quits for it.
      options.force_breakaway_from_job_ = true;
      return base::LaunchProcess(command, options).IsValid() ? Outcome::kInstalling : Outcome::kLaunch;
    }
  }
  base::DeleteFile(installer);
  return Outcome::kSignature;
}

}  // namespace

DesktopUpdates::Load::Load() = default;
DesktopUpdates::Load::Load(Load&&) = default;
DesktopUpdates::Load& DesktopUpdates::Load::operator=(Load&&) = default;
DesktopUpdates::Load::~Load() = default;

// static
DesktopUpdates& DesktopUpdates::Get() {
  static base::NoDestructor<DesktopUpdates> updates;
  return *updates;
}

DesktopUpdates::DesktopUpdates() = default;
DesktopUpdates::~DesktopUpdates() = default;

// static
std::string_view DesktopUpdates::OutcomeName(Outcome outcome) {
  switch (outcome) {
    case Outcome::kInstalling:
      return "installing";
    case Outcome::kDownload:
      return "download";
    case Outcome::kLength:
      return "length";
    case Outcome::kSignature:
      return "signature";
    case Outcome::kLaunch:
      return "launch";
    case Outcome::kUnavailable:
      return "unavailable";
  }
  return "unavailable";
}

void DesktopUpdates::ReadSettings(SettingsCallback done) {
  if (settings_) {
    std::move(done).Run(*settings_);
    return;
  }
  settings_waiting_.push_back(std::move(done));
  if (reading_settings_) return;
  reading_settings_ = true;
  // Only Crest as Setup installs it updates itself.
  if (!IsInstalledProduct()) {
    SettingsRead(std::nullopt);
    return;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&ReadSettingsFile, InstalledFolder().Append(FILE_PATH_LITERAL("update.json"))),
      base::BindOnce(&DesktopUpdates::SettingsRead, weak_factory_.GetWeakPtr()));
}

void DesktopUpdates::SettingsRead(std::optional<Settings> settings) {
  settings_.emplace(std::move(settings));
  reading_settings_ = false;
  std::vector<SettingsCallback> waiting = std::move(settings_waiting_);
  for (SettingsCallback& callback : waiting) std::move(callback).Run(*settings_);
}

void DesktopUpdates::FetchFeed(const std::string& name, FeedCallback done) {
  ReadSettings(base::BindOnce(&DesktopUpdates::FetchFeedWith, weak_factory_.GetWeakPtr(), name, std::move(done)));
}

void DesktopUpdates::FetchFeedWith(const std::string& name,
                                   FeedCallback done,
                                   const std::optional<Settings>& settings) {
  if (!settings || !IsFeedName(name)) {
    std::move(done).Run(std::nullopt);
    return;
  }
  auto request = std::make_unique<network::ResourceRequest>();
  request->url = settings->feed_base.Resolve(name);
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DISABLE_CACHE;
  const int load = next_load_++;
  Load& entry = loads_[load];
  entry.feed_done = std::move(done);
  entry.loader = network::SimpleURLLoader::Create(std::move(request), kUpdateAnnotation);
  entry.loader->SetTimeoutDuration(kFeedTimeout);
  entry.loader->SetRetryOptions(1, network::SimpleURLLoader::RETRY_ON_NETWORK_CHANGE);
  entry.loader->SetOnRedirectCallback(
      base::BindRepeating(&DesktopUpdates::Redirected, weak_factory_.GetWeakPtr(), load));
  entry.loader->DownloadToString(g_browser_process->shared_url_loader_factory().get(),
                                 base::BindOnce(&DesktopUpdates::FeedArrived, weak_factory_.GetWeakPtr(), load),
                                 kMaximumFeedBytes);
}

void DesktopUpdates::FeedArrived(int load, std::optional<std::string> text) {
  auto found = loads_.find(load);
  if (found == loads_.end()) return;
  Load done = std::move(found->second);
  loads_.erase(found);
  if (text && !base::IsStringUTF8AllowingNoncharacters(*text)) text.reset();
  std::move(done.feed_done).Run(std::move(text));
}

void DesktopUpdates::Install(const GURL& url,
                             int64_t length,
                             std::vector<uint8_t> signature,
                             ProgressCallback progress,
                             OutcomeCallback done) {
  if (installing_) {
    std::move(done).Run(Outcome::kUnavailable);
    return;
  }
  installing_ = true;
  ReadSettings(base::BindOnce(&DesktopUpdates::InstallWith, weak_factory_.GetWeakPtr(), url, length,
                              std::move(signature), std::move(progress), std::move(done)));
}

void DesktopUpdates::InstallWith(GURL url,
                                 int64_t length,
                                 std::vector<uint8_t> signature,
                                 ProgressCallback progress,
                                 OutcomeCallback done,
                                 const std::optional<Settings>& settings) {
  const int load = next_load_++;
  loads_[load].install_done = std::move(done);
  if (!settings) {
    Finish(load, Outcome::kUnavailable);
    return;
  }
  if (!AllowsUpdateURL(url) || length <= 0 || length > kMaximumInstallerBytes) {
    Finish(load, Outcome::kDownload);
    return;
  }
  if (signature.size() != 64) {
    Finish(load, Outcome::kSignature);
    return;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE}, base::BindOnce(&PrepareDownload),
      base::BindOnce(&DesktopUpdates::StartDownload, weak_factory_.GetWeakPtr(), load, std::move(url), length,
                     std::move(signature), std::move(progress)));
}

void DesktopUpdates::StartDownload(int load,
                                   GURL url,
                                   int64_t length,
                                   std::vector<uint8_t> signature,
                                   ProgressCallback progress,
                                   base::FilePath installer) {
  if (!loads_.contains(load)) return;
  if (installer.empty()) {
    Finish(load, Outcome::kDownload);
    return;
  }
  auto request = std::make_unique<network::ResourceRequest>();
  request->url = std::move(url);
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DISABLE_CACHE;
  Load& entry = loads_[load];
  entry.loader = network::SimpleURLLoader::Create(std::move(request), kUpdateAnnotation);
  entry.loader->SetRetryOptions(1, network::SimpleURLLoader::RETRY_ON_NETWORK_CHANGE);
  entry.loader->SetOnRedirectCallback(
      base::BindRepeating(&DesktopUpdates::Redirected, weak_factory_.GetWeakPtr(), load));
  entry.loader->SetOnDownloadProgressCallback(base::BindRepeating(
      [](ProgressCallback progress, int64_t total, uint64_t received) {
        progress.Run(static_cast<int64_t>(received), total);
      },
      std::move(progress), length));
  // A body longer than the feed said ends the download.
  entry.loader->DownloadToFile(
      g_browser_process->shared_url_loader_factory().get(),
      base::BindOnce(&DesktopUpdates::InstallerArrived, weak_factory_.GetWeakPtr(), load, length,
                     std::move(signature)),
      installer, length + 1);
}

void DesktopUpdates::InstallerArrived(int load,
                                      int64_t length,
                                      std::vector<uint8_t> signature,
                                      base::FilePath installer) {
  if (!loads_.contains(load)) return;
  if (installer.empty() || !settings_ || !*settings_) {
    Finish(load, Outcome::kDownload);
    return;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&CheckAndRun, std::move(installer), length, std::move(signature), (*settings_)->public_key),
      base::BindOnce(&DesktopUpdates::Finish, weak_factory_.GetWeakPtr(), load));
}

void DesktopUpdates::Finish(int load, Outcome outcome) {
  auto found = loads_.find(load);
  if (found == loads_.end()) return;
  Load done = std::move(found->second);
  loads_.erase(found);
  installing_ = false;
  if (done.install_done) std::move(done.install_done).Run(outcome);
  // Setup waits for Crest to quit, then installs and opens Crest again.
  if (outcome == Outcome::kInstalling) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce([] { DesktopHost::Get().Quit(); }));
  }
}

// A load that a redirect would take anywhere an update may not come from
// ends. Deleting the loader here is allowed.
void DesktopUpdates::Redirected(int load,
                                const GURL&,
                                const net::RedirectInfo& redirect,
                                const network::mojom::URLResponseHead&,
                                std::vector<std::string>*) {
  if (AllowsUpdateURL(redirect.new_url)) return;
  auto found = loads_.find(load);
  if (found == loads_.end()) return;
  if (found->second.feed_done) {
    FeedArrived(load, std::nullopt);
  } else {
    Finish(load, Outcome::kDownload);
  }
}

}  // namespace crest

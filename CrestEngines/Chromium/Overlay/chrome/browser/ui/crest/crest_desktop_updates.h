#ifndef CHROME_BROWSER_UI_CREST_CREST_DESKTOP_UPDATES_H_
#define CHROME_BROWSER_UI_CREST_CREST_DESKTOP_UPDATES_H_

#include <array>
#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "url/gurl.h"

namespace net {
struct RedirectInfo;
}

namespace network {
class SimpleURLLoader;
namespace mojom {
class URLResponseHead;
}
}  // namespace network

namespace crest {

// Crest for Windows' own updates, as Sparkle runs the Mac's. Packaging
// writes update.json beside chrome.exe: the build's version and number, the
// channel it was packaged for, the folder its feeds are in, and the Ed25519
// key its updates are signed with, the key that signs the Mac's. The
// interface reads a feed through `FetchFeed` and chooses the update in the
// sandboxed page it runs in; `Install` downloads it, checks that it is as
// long as the feed said and carries that key's signature, and runs its
// installer, which waits for Crest to quit, installs, and opens Crest again.
// A feed and an update come over https, or from this device for a local
// build's test.
class DesktopUpdates {
 public:
  // update.json, as packaging writes it.
  struct Settings {
    std::string version;
    int64_t build = 0;
    std::string channel;
    GURL feed_base;
    std::array<uint8_t, 32> public_key{};
  };

  // How an install went: the installer runs, or it didn't, because the
  // download failed or came out other than the feed said, the installer would
  // not start, or this Crest can't update.
  enum class Outcome {
    kInstalling,
    kDownload,
    kLength,
    kSignature,
    kLaunch,
    kUnavailable,
  };

  using SettingsCallback = base::OnceCallback<void(const std::optional<Settings>&)>;
  using FeedCallback = base::OnceCallback<void(std::optional<std::string>)>;
  using ProgressCallback = base::RepeatingCallback<void(int64_t received, int64_t total)>;
  using OutcomeCallback = base::OnceCallback<void(Outcome)>;

  static DesktopUpdates& Get();

  DesktopUpdates(const DesktopUpdates&) = delete;
  DesktopUpdates& operator=(const DesktopUpdates&) = delete;

  // The outcome as the interface names a failure, or "installing".
  static std::string_view OutcomeName(Outcome outcome);

  // This build's update.json, read once; none where Crest isn't installed.
  void ReadSettings(SettingsCallback done);
  // The feed `name`, such as appcast-windows.xml, from the folder the
  // settings name, as text, or none when it didn't arrive.
  void FetchFeed(const std::string& name, FeedCallback done);
  // Downloads the installer at `url`, checks it, and runs it. `progress`
  // hears the download; `done` hears the outcome. One install runs at a time.
  void Install(const GURL& url,
               int64_t length,
               std::vector<uint8_t> signature,
               ProgressCallback progress,
               OutcomeCallback done);

 private:
  friend class base::NoDestructor<DesktopUpdates>;

  // A download under way: its loader and who hears how it ends.
  struct Load {
    Load();
    Load(Load&&);
    Load& operator=(Load&&);
    ~Load();
    std::unique_ptr<network::SimpleURLLoader> loader;
    FeedCallback feed_done;
    OutcomeCallback install_done;
  };

  DesktopUpdates();
  ~DesktopUpdates();

  void SettingsRead(std::optional<Settings> settings);
  void FetchFeedWith(const std::string& name, FeedCallback done, const std::optional<Settings>& settings);
  void FeedArrived(int load, std::optional<std::string> text);
  void InstallWith(GURL url,
                   int64_t length,
                   std::vector<uint8_t> signature,
                   ProgressCallback progress,
                   OutcomeCallback done,
                   const std::optional<Settings>& settings);
  void StartDownload(int load,
                     GURL url,
                     int64_t length,
                     std::vector<uint8_t> signature,
                     ProgressCallback progress,
                     base::FilePath installer);
  void InstallerArrived(int load, int64_t length, std::vector<uint8_t> signature, base::FilePath installer);
  void Finish(int load, Outcome outcome);
  // A redirect anywhere an update may not come from ends the load.
  void Redirected(int load,
                  const GURL& url_before_redirect,
                  const net::RedirectInfo& redirect,
                  const network::mojom::URLResponseHead& head,
                  std::vector<std::string>* removed_headers);

  // update.json once read: unset until then, then the settings or none.
  std::optional<std::optional<Settings>> settings_;
  std::vector<SettingsCallback> settings_waiting_;
  bool reading_settings_ = false;
  std::map<int, Load> loads_;
  int next_load_ = 0;
  bool installing_ = false;
  base::WeakPtrFactory<DesktopUpdates> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_DESKTOP_UPDATES_H_

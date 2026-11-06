#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_STORE_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_STORE_H_

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "url/gurl.h"

class Profile;

namespace content {
class RenderFrameHost;
class WebContents;
}

namespace extensions {
class CrxInstallError;
}

namespace network {
class SharedURLLoaderFactory;
class SimpleURLLoader;
namespace mojom {
class URLResponseHead;
}
}  // namespace network

namespace crest {

class EngineBinding;

// A Chrome Web Store listing in a page. Crest owns the store's Add to Chrome
// button, so an install goes through Crest's review and Spaces rather than
// Chromium's own installer: a script in an isolated world on the store's own
// host relabels the button and asks Crest to run its install review. The script is not a general scripting entry
// point — it is injected only into the store's own main frame in a regular
// profile, where a Space's persistent extensions live, and the only request
// it can make is for the extension the page's own URL names.
class PageStore final {
 public:
  using Present = base::RepeatingCallback<void(engine::EnginePresentation)>;

  PageStore(content::WebContents* contents, const engine::Guid& page, Present present);
  PageStore(const PageStore&) = delete;
  PageStore& operator=(const PageStore&) = delete;
  ~PageStore();

  // The main frame's document can take the listing's script.
  void DocumentAvailable();
  // A move within the listing's document committed at `url`. True when it was
  // the listing's request, written into its own fragment, which is Crest's
  // message rather than a page anyone records.
  bool Committed(const GURL& url);
  // The review the listing's request began finished, or never started: its
  // button goes back to what the engine's registry says.
  void RequestFinished();
  // Restates the listing's button from the engine's registry.
  void Refresh();

 private:
  content::RenderFrameHost* Frame() const;
  void Run(const std::string& script);
  bool Consume(const GURL& url);

  const raw_ptr<content::WebContents> contents_;
  const engine::Guid page_;
  const Present present_;
  // A request from the listing is still with Crest.
  bool request_open_ = false;
};

// One Chrome Web Store package download, made by a Space's own profile with
// the request Chromium's Web Store installer sends. Crest downloads it here
// rather than through that installer, so one package can be installed into
// every Space the person picks, and Chromium's CrxInstaller judges it in each;
// nothing here limits or inspects it. It asks without cookies, as Chromium's
// installer does for a public item, and asks once more with the profile's
// cookies when the service refuses, since a private or trusted-tester item is
// served only to an account that can see it. Destroying it stops the request
// and deletes what it received.
class WebStoreDownload final {
 public:
  // The fraction of the package received, once the response names its size.
  using Progress = base::RepeatingCallback<void(double fraction)>;
  // The package file, which the caller then owns, or nothing.
  using Done = base::OnceCallback<void(std::optional<base::FilePath> package)>;

  WebStoreDownload(Profile* profile, const std::string& extension_id, Progress progress, Done done);
  WebStoreDownload(const WebStoreDownload&) = delete;
  WebStoreDownload& operator=(const WebStoreDownload&) = delete;
  ~WebStoreDownload();

 private:
  // Requests the package, with the profile's cookies or without.
  void Begin(bool with_cookies);
  void Started(const GURL& url, const network::mojom::URLResponseHead& head);
  void Progressed(uint64_t received);
  void Finished(base::FilePath path);

  const scoped_refptr<network::SharedURLLoaderFactory> factory_;
  const GURL url_;
  bool with_cookies_ = false;
  std::unique_ptr<network::SimpleURLLoader> loader_;
  int64_t length_ = -1;
  const Progress progress_;
  Done done_;
};

// The extension installs the core runs on Chromium, by install: each one's
// package, downloaded once through the profile the core names and kept until
// the core ends the install, and installed into each profile the core names
// next, which Chromium verifies again there. The question each install asks
// goes to the core, never to a window, and the core answers it: from the
// person's review, or from the consent they gave the same package before.
class ExtensionInstalls final {
 public:
  explicit ExtensionInstalls(EngineBinding& binding);
  ExtensionInstalls(const ExtensionInstalls&) = delete;
  ExtensionInstalls& operator=(const ExtensionInstalls&) = delete;
  ~ExtensionInstalls();

  void Download(const engine::DownloadExtension& command);
  void Install(const engine::InstallExtensionPackage& command);
  void End(const engine::EndExtensionInstall& command);

 private:
  struct Running;

  // The install the core runs as `install`, or nullptr once it ended.
  Running* Find(const engine::Guid& install);
  void StartDownload(const engine::Guid& install, const engine::Guid& profile, bool ready);
  void Progressed(const engine::Guid& install, double fraction);
  void Downloaded(const engine::Guid& install, const engine::Guid& profile, std::optional<base::FilePath> package);
  void StagePackage(const engine::Guid& install, const engine::Guid& profile, bool ready);
  void Staged(const engine::Guid& install, const engine::Guid& profile, base::FilePath staged);
  void Installed(const engine::Guid& install,
                 const engine::Guid& profile,
                 const std::optional<extensions::CrxInstallError>& error);
  void Fail(const engine::Guid& install, const engine::Guid& profile, engine::ExtensionInstallFailure reason);

  const raw_ref<EngineBinding> binding_;
  std::map<engine::Guid, std::unique_ptr<Running>> installs_;
  base::WeakPtrFactory<ExtensionInstalls> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_STORE_H_

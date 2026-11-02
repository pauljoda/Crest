#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_DOCUMENTS_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_DOCUMENTS_H_

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"
#include "base/types/expected.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "content/public/browser/devtools_agent_host_client.h"
#include "content/public/browser/web_contents_observer.h"

namespace base {
class DictValue;
}

namespace content {
class DevToolsAgentHost;
}

namespace crest {

// Exports one page's document through a fixed set of in-process DevTools
// commands for exactly that page: a PDF as it prints, a full-page PNG, or an
// MHTML archive. It opens no debugging socket and offers no general protocol
// or evaluation entry point. One export runs at a time; it ends when the page
// navigates to another document, loses its renderer or closes, and after 45
// seconds.
//
// The GPU draws a capture into one surface, which can be no taller than its
// texture limit, so a full-page image taller than a band is captured band by
// band and the bands joined into one image. Joining holds the whole image at
// once, so an image with more pixels than that allows is refused as too large
// before any capture.
class PageDocuments final : public content::WebContentsObserver,
                            public content::DevToolsAgentHostClient {
 public:
  // The exported document, or why there is none.
  using Done = base::OnceCallback<void(std::optional<std::vector<uint8_t>> document,
                                       std::optional<engine::PageExportFailure> failure)>;

  explicit PageDocuments(content::WebContents* contents);
  PageDocuments(const PageDocuments&) = delete;
  PageDocuments& operator=(const PageDocuments&) = delete;
  ~PageDocuments() override;

  // Exports the document as `format`, a full-page image `width` points wide
  // or at its own width when `width` is 0, and answers `done`, never on the
  // stack of this call.
  void Export(engine::PageExportFormat format, double width, Done done);

 private:
  // content::DevToolsAgentHostClient:
  void DispatchProtocolMessage(content::DevToolsAgentHost* host, base::span<const uint8_t> message) override;
  void AgentHostClosed(content::DevToolsAgentHost* host) override;

  // content::WebContentsObserver:
  void DidStartNavigation(content::NavigationHandle* navigation) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) override;
  void WebContentsDestroyed() override;

  void Send(const char* method, base::DictValue params);
  // Captures the page from `top`, in pixels of the finished image, down to
  // the next band's top or the image's bottom.
  void CaptureBand(int top);
  // The capture of a band whose image is `band`.
  void Captured(std::vector<uint8_t> band);
  void Joined(base::expected<std::vector<uint8_t>, engine::PageExportFailure> document);
  void Finish(std::optional<std::vector<uint8_t>> document, std::optional<engine::PageExportFailure> failure);

  scoped_refptr<content::DevToolsAgentHost> agent_;
  base::OneShotTimer timer_;
  bool attached_ = false;
  bool measuring_ = false;
  int sequence_ = 0;
  double width_ = 0;
  engine::PageExportFormat format_ = engine::PageExportFormat::kPdf;
  // The full-page image being captured in bands: the page's width in CSS
  // pixels, the scale the caller asked for, the image pixels per CSS pixel,
  // the image's height in pixels, the top of the band being captured, and
  // the bands captured so far.
  double capture_width_ = 0;
  double capture_scale_ = 1;
  double pixels_per_css_pixel_ = 1;
  int image_height_ = 0;
  int band_top_ = 0;
  std::vector<std::vector<uint8_t>> bands_;
  Done done_;
  base::WeakPtrFactory<PageDocuments> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_DOCUMENTS_H_

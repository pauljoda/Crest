#include "chrome/browser/ui/crest/crest_engine_documents.h"

#include <algorithm>
#include <cmath>
#include <utility>

#include "base/base64.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "base/values.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/gfx/codec/png_codec.h"

namespace crest {

namespace {

// The largest full-page image, in CSS pixels, and the largest image width a
// caller may ask for.
constexpr double kMaximumWidth = 6000;
constexpr double kMaximumHeight = 24000;
// The width a full-page image takes when the caller names none.
constexpr double kDefaultWidth = 1600;
// The largest protocol message and exported document the page accepts.
constexpr size_t kMaximumMessageBytes = 96 * 1024 * 1024;
constexpr size_t kMaximumDocumentBytes = 64 * 1024 * 1024;
constexpr base::TimeDelta kTimeout = base::Seconds(45);
// The tallest band of a full-page image the GPU draws at once, in image
// pixels: half the 16,384-pixel texture limit of the GPUs Crest runs on.
constexpr int kMaximumBandHeight = 8192;
// The most pixels a full-page image may have. Joining its bands holds them all
// at once: a gigabyte of decoded pixels at this size.
constexpr double kMaximumImagePixels = 256.0 * 1024 * 1024;

// Joins the bands of a full-page image, top to bottom, into one PNG `height`
// pixels tall. Decoding and encoding a tall page's pixels takes a while, so
// this runs away from the UI thread.
base::expected<std::vector<uint8_t>, engine::PageExportFailure> JoinBands(std::vector<std::vector<uint8_t>> bands,
                                                                          int height) {
  SkBitmap image;
  int top = 0;
  for (std::vector<uint8_t>& band : bands) {
    const SkBitmap pixels = gfx::PNGCodec::Decode(band);
    if (pixels.drawsNothing()) {
      return base::unexpected(engine::PageExportFailure::kFailed);
    }
    if (image.drawsNothing()) {
      if (!image.tryAllocN32Pixels(pixels.width(), height)) {
        return base::unexpected(engine::PageExportFailure::kTooLarge);
      }
      image.eraseColor(SK_ColorTRANSPARENT);
    }
    image.writePixels(pixels.pixmap(), 0, top);
    top += pixels.height();
    std::vector<uint8_t>().swap(band);
  }
  std::optional<std::vector<uint8_t>> document =
      gfx::PNGCodec::EncodeBGRASkBitmap(image, /*discard_transparency=*/false);
  if (!document) {
    return base::unexpected(engine::PageExportFailure::kFailed);
  }
  return std::move(*document);
}

}  // namespace

PageDocuments::PageDocuments(content::WebContents* contents) : content::WebContentsObserver(contents) {}

PageDocuments::~PageDocuments() {
  Finish(std::nullopt, engine::PageExportFailure::kClosed);
}

void PageDocuments::Export(engine::PageExportFormat format, double width, Done done) {
  if (done_) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(done), std::optional<std::vector<uint8_t>>(),
                                  std::optional<engine::PageExportFailure>(engine::PageExportFailure::kBusy)));
    return;
  }
  done_ = std::move(done);
  if (!web_contents() || !std::isfinite(width) || width < 0 || width > kMaximumWidth) {
    Finish(std::nullopt, engine::PageExportFailure::kUnsupported);
    return;
  }
  format_ = format;
  width_ = width;
  agent_ = content::DevToolsAgentHost::GetOrCreateFor(web_contents());
  attached_ = agent_ && agent_->AttachClient(this);
  if (!attached_) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  timer_.Start(FROM_HERE, kTimeout,
               base::BindOnce(&PageDocuments::Finish, base::Unretained(this), std::optional<std::vector<uint8_t>>(),
                              std::optional<engine::PageExportFailure>(engine::PageExportFailure::kTimedOut)));
  switch (format) {
    case engine::PageExportFormat::kPdf:
      Send("Page.printToPDF",
           base::DictValue().Set("printBackground", true).Set("preferCSSPageSize", true).Set("generateTaggedPDF", true));
      break;
    case engine::PageExportFormat::kMhtml:
      Send("Page.captureSnapshot", base::DictValue().Set("format", "mhtml"));
      break;
    case engine::PageExportFormat::kPng:
      measuring_ = true;
      Send("Page.getLayoutMetrics", base::DictValue());
      break;
    case engine::PageExportFormat::kWebArchive:
      Finish(std::nullopt, engine::PageExportFailure::kUnsupported);
      break;
  }
}

void PageDocuments::DispatchProtocolMessage(content::DevToolsAgentHost*, base::span<const uint8_t> message) {
  if (!done_) {
    return;
  }
  if (message.size() > kMaximumMessageBytes) {
    Finish(std::nullopt, engine::PageExportFailure::kTooLarge);
    return;
  }
  auto response = base::JSONReader::ReadDict(base::as_string_view(message), base::JSON_PARSE_RFC);
  if (!response || response->FindInt("id") != sequence_) {
    return;
  }
  const auto* result = response->FindDict("result");
  if (!result) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  if (measuring_) {
    measuring_ = false;
    const auto* dimensions = result->FindDict("cssContentSize");
    double width = dimensions ? dimensions->FindDouble("width").value_or(0) : 0;
    double height = dimensions ? dimensions->FindDouble("height").value_or(0) : 0;
    if (!std::isfinite(width) || !std::isfinite(height) || width <= 0 || height <= 0) {
      Finish(std::nullopt, engine::PageExportFailure::kFailed);
      return;
    }
    width = std::min(width, kMaximumWidth);
    height = std::min(height, kMaximumHeight);
    const double target = width_ > 0 ? width_ : std::min(width, kDefaultWidth);
    // The image has the screen's pixels: the page draws `target` points wide
    // at its device scale.
    const content::RenderWidgetHostView* view = web_contents()->GetRenderWidgetHostView();
    capture_width_ = width;
    capture_scale_ = target / width;
    pixels_per_css_pixel_ = capture_scale_ * (view ? view->GetDeviceScaleFactor() : 1);
    // A width larger than the page's scales the image up, so its size is
    // checked before anything is captured.
    const double image_height = height * pixels_per_css_pixel_;
    if (width * pixels_per_css_pixel_ * image_height > kMaximumImagePixels) {
      Finish(std::nullopt, engine::PageExportFailure::kTooLarge);
      return;
    }
    image_height_ = std::max(1, static_cast<int>(std::lround(image_height)));
    bands_.clear();
    CaptureBand(0);
    return;
  }
  const std::string* encoded = result->FindString("data");
  if (!encoded) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  // An archive arrives as its text; a PDF or an image as base64.
  std::optional<std::vector<uint8_t>> document =
      format_ == engine::PageExportFormat::kMhtml ? std::vector<uint8_t>(encoded->begin(), encoded->end())
                                                  : base::Base64Decode(*encoded);
  if (!document || document->empty()) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  if (format_ == engine::PageExportFormat::kPng) {
    Captured(std::move(*document));
    return;
  }
  if (document->size() > kMaximumDocumentBytes) {
    Finish(std::nullopt, engine::PageExportFailure::kTooLarge);
    return;
  }
  Finish(std::move(document), std::nullopt);
}

void PageDocuments::AgentHostClosed(content::DevToolsAgentHost*) {
  attached_ = false;
  agent_.reset();
  Finish(std::nullopt, engine::PageExportFailure::kClosed);
}

void PageDocuments::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) {
    Finish(std::nullopt, engine::PageExportFailure::kNavigated);
  }
}

void PageDocuments::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) {
  Finish(std::nullopt, engine::PageExportFailure::kRendererStopped);
}

void PageDocuments::WebContentsDestroyed() {
  Finish(std::nullopt, engine::PageExportFailure::kClosed);
  Observe(nullptr);
}

void PageDocuments::Send(const char* method, base::DictValue params) {
  if (!done_ || !agent_) {
    return;
  }
  auto json = base::WriteJson(
      base::DictValue().Set("id", ++sequence_).Set("method", method).Set("params", std::move(params)));
  if (!json) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  agent_->DispatchProtocolMessage(this, base::as_byte_span(*json));
}

void PageDocuments::CaptureBand(int top) {
  band_top_ = top;
  const int bottom = std::min(image_height_, top + kMaximumBandHeight);
  auto clip = base::DictValue()
                  .Set("x", 0)
                  .Set("y", top / pixels_per_css_pixel_)
                  .Set("width", capture_width_)
                  .Set("height", (bottom - top) / pixels_per_css_pixel_)
                  .Set("scale", capture_scale_);
  Send("Page.captureScreenshot", base::DictValue()
                                     .Set("format", "png")
                                     .Set("fromSurface", true)
                                     .Set("captureBeyondViewport", true)
                                     .Set("clip", std::move(clip)));
}

// A page that fits one band is its own image. A taller one is captured band
// by band, and its bands are joined once the last arrives.
void PageDocuments::Captured(std::vector<uint8_t> band) {
  const int bottom = std::min(image_height_, band_top_ + kMaximumBandHeight);
  if (bands_.empty() && bottom == image_height_) {
    Joined(std::move(band));
    return;
  }
  bands_.push_back(std::move(band));
  if (bottom < image_height_) {
    CaptureBand(bottom);
    return;
  }
  std::vector<std::vector<uint8_t>> bands;
  bands.swap(bands_);
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::TaskPriority::USER_VISIBLE, base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce(&JoinBands, std::move(bands), image_height_),
      base::BindOnce(&PageDocuments::Joined, weak_factory_.GetWeakPtr()));
}

void PageDocuments::Joined(base::expected<std::vector<uint8_t>, engine::PageExportFailure> document) {
  if (!document.has_value()) {
    Finish(std::nullopt, document.error());
    return;
  }
  if (document->size() > kMaximumDocumentBytes) {
    Finish(std::nullopt, engine::PageExportFailure::kTooLarge);
    return;
  }
  Finish(std::move(*document), std::nullopt);
}

// Answers on a task of its own: whoever asked may let the page go when it
// hears, and must not do so on the protocol's stack. A join still running
// for an export that has ended answers no one.
void PageDocuments::Finish(std::optional<std::vector<uint8_t>> document,
                           std::optional<engine::PageExportFailure> failure) {
  Done done = std::move(done_);
  measuring_ = false;
  bands_.clear();
  weak_factory_.InvalidateWeakPtrs();
  timer_.Stop();
  if (attached_ && agent_) {
    attached_ = false;
    agent_->DetachClient(this);
  }
  agent_.reset();
  if (done) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(done), std::move(document), failure));
  }
}

}  // namespace crest

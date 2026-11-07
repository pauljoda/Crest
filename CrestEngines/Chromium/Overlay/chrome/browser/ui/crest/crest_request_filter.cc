#include "chrome/browser/ui/crest/crest_request_filter.h"

#include <dlfcn.h>

#include <atomic>
#include <optional>
#include <string>
#include <utility>

#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/crest/crest_content_filter.h"
#include "chrome/browser/ui/crest/crest_core.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/receiver_set.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "net/base/net_errors.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/url_loader_completion_status.h"
#include "services/network/public/cpp/url_loader_factory_builder.h"
#include "services/network/public/mojom/fetch_api.mojom.h"
#include "services/network/public/mojom/url_loader.mojom.h"
#include "services/network/public/mojom/url_loader_factory.mojom.h"

namespace crest {

namespace {

using SlotCheck = int32_t (*)(const crest_content_filter_slot_t* slot,
                              const crest_content_filter_request_t* request,
                              crest_content_filter_decision_t* decision);
using SlotAddress = crest_status_t(CREST_CALL*)(uint64_t app, void** slot);

// The core's content filter, found once: the slot the core keeps the filter in
// force in, and the check its library exports.
struct ContentFilter {
  std::atomic<const crest_content_filter_slot_t*> slot{nullptr};
  std::atomic<SlotCheck> check{nullptr};
};

ContentFilter& Filter() {
  static ContentFilter filter;
  return filter;
}

// The sequence every filter checks its requests on, away from the UI thread
// the platform's interface shares.
scoped_refptr<base::SequencedTaskRunner> FilterSequence() {
  static base::NoDestructor<scoped_refptr<base::SequencedTaskRunner>> sequence(
      base::ThreadPool::CreateSequencedTaskRunner({base::TaskPriority::USER_BLOCKING}));
  return *sequence;
}

// What the content filter calls a request's destination. A main frame's or a
// fenced frame's own document is never filtered.
std::optional<uint8_t> KindOf(network::mojom::RequestDestination destination) {
  using Destination = network::mojom::RequestDestination;
  switch (destination) {
    case Destination::kDocument:
    case Destination::kFencedframe:
      return std::nullopt;
    case Destination::kFrame:
    case Destination::kIframe:
      return CREST_CONTENT_FILTER_SUBDOCUMENT;
    case Destination::kScript:
    case Destination::kWorker:
    case Destination::kSharedWorker:
    case Destination::kServiceWorker:
      return CREST_CONTENT_FILTER_SCRIPT;
    case Destination::kStyle:
      return CREST_CONTENT_FILTER_STYLESHEET;
    case Destination::kImage:
      return CREST_CONTENT_FILTER_IMAGE;
    case Destination::kFont:
      return CREST_CONTENT_FILTER_FONT;
    case Destination::kAudio:
    case Destination::kVideo:
    case Destination::kTrack:
      return CREST_CONTENT_FILTER_MEDIA;
    case Destination::kObject:
    case Destination::kEmbed:
      return CREST_CONTENT_FILTER_OBJECT;
    case Destination::kReport:
      return CREST_CONTENT_FILTER_CSP_REPORT;
    case Destination::kEmpty:
      return CREST_CONTENT_FILTER_XMLHTTPREQUEST;
    default:
      return CREST_CONTENT_FILTER_OTHER;
  }
}

uint8_t MethodOf(const std::string& method) {
  if (method == "GET") return CREST_CONTENT_FILTER_GET;
  if (method == "POST") return CREST_CONTENT_FILTER_POST;
  if (method == "HEAD") return CREST_CONTENT_FILTER_HEAD;
  if (method == "PUT") return CREST_CONTENT_FILTER_PUT;
  if (method == "DELETE") return CREST_CONTENT_FILTER_DELETE;
  if (method == "OPTIONS") return CREST_CONTENT_FILTER_OPTIONS;
  if (method == "PATCH") return CREST_CONTENT_FILTER_PATCH;
  if (method == "CONNECT") return CREST_CONTENT_FILTER_CONNECT;
  return CREST_CONTENT_FILTER_METHOD_OTHER;
}

crest_content_filter_text_t Text(const std::string& text) {
  return {reinterpret_cast<const uint8_t*>(text.data()), text.size()};
}

// A factory in front of the one a page's document or frame navigation would
// use, which fails each request the content filter blocks and hands the rest
// on unchanged. It lives on the filter sequence and goes away with its last
// pipe.
class FilteringFactory final : public network::mojom::URLLoaderFactory {
 public:
  static void Start(mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver,
                    mojo::PendingRemote<network::mojom::URLLoaderFactory> target,
                    scoped_refptr<PageFilter> page) {
    new FilteringFactory(std::move(receiver), std::move(target), std::move(page));
  }

  FilteringFactory(const FilteringFactory&) = delete;
  FilteringFactory& operator=(const FilteringFactory&) = delete;

  void CreateLoaderAndStart(mojo::PendingReceiver<network::mojom::URLLoader> loader,
                            int32_t request_id,
                            uint32_t options,
                            const network::ResourceRequest& request,
                            mojo::PendingRemote<network::mojom::URLLoaderClient> client,
                            const net::MutableNetworkTrafficAnnotationTag& annotation) override {
    if (Blocks(request)) {
      mojo::Remote<network::mojom::URLLoaderClient>(std::move(client))
          ->OnComplete(network::URLLoaderCompletionStatus(net::ERR_BLOCKED_BY_CLIENT));
      return;
    }
    target_->CreateLoaderAndStart(std::move(loader), request_id, options, request, std::move(client), annotation);
  }

  void Clone(mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver) override {
    receivers_.Add(this, std::move(receiver));
  }

 private:
  FilteringFactory(mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver,
                   mojo::PendingRemote<network::mojom::URLLoaderFactory> target,
                   scoped_refptr<PageFilter> page)
      : target_(std::move(target)), page_(std::move(page)) {
    receivers_.Add(this, std::move(receiver));
    receivers_.set_disconnect_handler(
        base::BindRepeating(&FilteringFactory::ReceiverGone, base::Unretained(this)));
    target_.set_disconnect_handler(base::BindOnce(&FilteringFactory::TargetGone, base::Unretained(this)));
  }

  ~FilteringFactory() override = default;

  void ReceiverGone() {
    if (receivers_.empty()) delete this;
  }

  void TargetGone() { delete this; }

  // Whether the filter in force blocks `request` for the page. A request of
  // a page that blocks nothing, or one before the core's filter is found,
  // goes through.
  bool Blocks(const network::ResourceRequest& request) const {
    const crest_content_filter_slot_t* slot = Filter().slot.load();
    const SlotCheck check = Filter().check.load();
    if (!slot || !check || !page_->Blocks()) return false;
    if (!request.url.SchemeIsHTTPOrHTTPS() && !request.url.SchemeIsWSOrWSS()) return false;
    const std::optional<uint8_t> kind = KindOf(request.destination);
    if (!kind) return false;
    const std::string& url = request.url.possibly_invalid_spec();
    const std::string source =
        request.request_initiator ? request.request_initiator->GetURL().possibly_invalid_spec() : url;
    const crest_content_filter_request_t asked{Text(url), Text(source), *kind, MethodOf(request.method)};
    crest_content_filter_decision_t decision{CREST_CONTENT_FILTER_ALLOW};
    return check(slot, &asked, &decision) == CREST_CONTENT_FILTER_OK &&
           decision.verdict == CREST_CONTENT_FILTER_BLOCK;
  }

  mojo::ReceiverSet<network::mojom::URLLoaderFactory> receivers_;
  mojo::Remote<network::mojom::URLLoaderFactory> target_;
  const scoped_refptr<PageFilter> page_;
};

}  // namespace

void FilterRequests(content::RenderFrameHost* frame,
                    content::ContentBrowserClient::URLLoaderFactoryType type,
                    network::URLLoaderFactoryBuilder& builder) {
  using Type = content::ContentBrowserClient::URLLoaderFactoryType;
  if (!IsEnabled() || !frame || (type != Type::kDocumentSubResource && type != Type::kNavigation)) return;
  EnginePage* page = EngineBinding::Get().PageFor(content::WebContents::FromRenderFrameHost(frame));
  if (!page) return;
  auto [receiver, target] = builder.Append();
  FilterSequence()->PostTask(FROM_HERE, base::BindOnce(&FilteringFactory::Start, std::move(receiver),
                                                       std::move(target), page->RequestFilter()));
}

void UseContentFilter(uint64_t app) {
  if (Filter().check.load()) return;
  // The core's library exports both: the slot's address through the app, and
  // the check every request goes through.
  auto slot_address = reinterpret_cast<SlotAddress>(dlsym(RTLD_DEFAULT, "crest_app_content_filter_slot"));
  auto check = reinterpret_cast<SlotCheck>(dlsym(RTLD_DEFAULT, "crest_content_filter_slot_check"));
  void* slot = nullptr;
  if (!slot_address || !check || slot_address(app, &slot) != CREST_OK || !slot) return;
  Filter().slot.store(static_cast<const crest_content_filter_slot_t*>(slot));
  Filter().check.store(check);
}

}  // namespace crest

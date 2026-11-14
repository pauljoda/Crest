#include "chrome/browser/ui/crest/crest_request_filter.h"

#include <dlfcn.h>

#include <algorithm>
#include <atomic>
#include <optional>
#include <string>
#include <utility>

#include "base/base64.h"
#include "base/byte_size.h"
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
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/system/data_pipe.h"
#include "net/base/isolation_info.h"
#include "net/base/net_errors.h"
#include "net/http/http_response_headers.h"
#include "net/url_request/redirect_info.h"
#include "services/network/public/cpp/http_request_headers_update_params.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/url_loader_completion_status.h"
#include "services/network/public/cpp/url_loader_factory_builder.h"
#include "services/network/public/mojom/early_hints.mojom.h"
#include "services/network/public/mojom/fetch_api.mojom.h"
#include "services/network/public/mojom/url_loader.mojom.h"
#include "services/network/public/mojom/url_loader_factory.mojom.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "url/origin.h"
#include "url/scheme_host_port.h"

namespace crest {

namespace {

using SlotCheck = int32_t (*)(const crest_content_filter_slot_t* slot,
                              const crest_content_filter_request_t* request,
                              crest_content_filter_decision_t* decision,
                              crest_content_filter_buffer_t* redirect);
using BufferFree = void (*)(crest_content_filter_buffer_t* buffer);
using SlotAddress = crest_status_t(CREST_CALL*)(uint64_t app, void** slot);

// The core's content filter, found once: the slot the core keeps the filter in
// force in, and the check and buffer release its library exports.
struct ContentFilter {
  std::atomic<const crest_content_filter_slot_t*> slot{nullptr};
  std::atomic<SlotCheck> check{nullptr};
  std::atomic<BufferFree> free{nullptr};
};

// What the filter decided for a request, and for a redirect, the resource to
// serve in its place.
struct Verdict {
  uint8_t verdict = CREST_CONTENT_FILTER_ALLOW;
  std::string redirect;
};

// Answers `client` with `body` as a resource of `mime`, as a server would, in
// place of a request the filter redirected.
void Serve(network::mojom::URLLoaderClient& client, const std::string& mime, const std::string& body) {
  mojo::ScopedDataPipeProducerHandle producer;
  mojo::ScopedDataPipeConsumerHandle consumer;
  if (mojo::CreateDataPipe(std::max<size_t>(body.size(), 1), producer, consumer) != MOJO_RESULT_OK) {
    client.OnComplete(network::URLLoaderCompletionStatus(net::ERR_BLOCKED_BY_CLIENT));
    return;
  }
  size_t written = 0;
  if (!body.empty() &&
      producer->WriteData(base::as_byte_span(body), MOJO_WRITE_DATA_FLAG_ALL_OR_NONE, written) != MOJO_RESULT_OK) {
    client.OnComplete(network::URLLoaderCompletionStatus(net::ERR_BLOCKED_BY_CLIENT));
    return;
  }
  producer.reset();
  auto head = network::mojom::URLResponseHead::New();
  head->headers = base::MakeRefCounted<net::HttpResponseHeaders>("HTTP/1.1 200 OK");
  head->headers->SetHeader("Content-Type", mime);
  head->headers->SetHeader("Access-Control-Allow-Origin", "*");
  head->mime_type = mime;
  head->content_length = static_cast<int64_t>(body.size());
  client.OnReceiveResponse(std::move(head), std::move(consumer), std::nullopt);
  network::URLLoaderCompletionStatus status(net::OK);
  status.decoded_body_length = base::ByteSize(body.size());
  client.OnComplete(status);
}

// The type and bytes of a `data:<type>;base64,<bytes>` URL, or nothing for a
// URL in another form.
std::optional<std::pair<std::string, std::string>> DataURL(const std::string& url) {
  static constexpr char kPrefix[] = "data:";
  static constexpr char kBase64[] = ";base64,";
  if (!url.starts_with(kPrefix)) {
    return std::nullopt;
  }
  size_t marker = url.find(kBase64);
  if (marker == std::string::npos) {
    return std::nullopt;
  }
  std::string body;
  if (!base::Base64Decode(std::string_view(url).substr(marker + sizeof(kBase64) - 1), &body)) {
    return std::nullopt;
  }
  return std::make_pair(url.substr(sizeof(kPrefix) - 1, marker - (sizeof(kPrefix) - 1)), std::move(body));
}

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

// What a request asks for, or the request a redirect makes of it.
struct Asked {
  GURL url;
  std::string method;
  network::mojom::RequestDestination destination;
  std::optional<url::Origin> initiator;
};

bool IsFrame(network::mojom::RequestDestination destination) {
  return destination == network::mojom::RequestDestination::kIframe ||
         destination == network::mojom::RequestDestination::kFrame;
}

// What the filter in force decides for `asked` of a page that shows `top`,
// the top-level page the request belongs to, as Brave passes it: a filter's
// `$domain` and `$third-party` options and the site's own rules are about
// that page, never the frame that asks. A request of a page that blocks
// nothing, or one before the core's filter is found, goes through.
Verdict Decide(const Asked& asked, const PageFilter& page, const std::string& top) {
  const crest_content_filter_slot_t* slot = Filter().slot.load();
  const SlotCheck check = Filter().check.load();
  const BufferFree free = Filter().free.load();
  if (!slot || !check || !free || !page.Blocks()) return {};
  if (!asked.url.SchemeIsHTTPOrHTTPS() && !asked.url.SchemeIsWSOrWSS()) return {};
  const std::optional<uint8_t> kind = KindOf(asked.destination);
  if (!kind) return {};
  const std::string& url = asked.url.possibly_invalid_spec();
  const std::string source = !top.empty()       ? top
                             : asked.initiator ? asked.initiator->GetURL().possibly_invalid_spec()
                                               : url;
  const crest_content_filter_request_t request{Text(url), Text(source), *kind, MethodOf(asked.method)};
  crest_content_filter_decision_t decision{CREST_CONTENT_FILTER_ALLOW};
  crest_content_filter_buffer_t redirect{nullptr, 0};
  if (check(slot, &request, &decision, &redirect) != CREST_CONTENT_FILTER_OK) return {};
  Verdict verdict{decision.verdict, {}};
  if (redirect.bytes) {
    verdict.redirect.assign(reinterpret_cast<const char*>(redirect.bytes), redirect.length);
    free(&redirect);
  }
  return verdict;
}

// Answers `client` for a request or hop the filter did not allow: with the
// resource it redirects to, for anything but a frame, or as blocked.
void Refuse(network::mojom::URLLoaderClient& client, const Verdict& verdict,
            network::mojom::RequestDestination destination) {
  if (verdict.verdict == CREST_CONTENT_FILTER_REDIRECT && !IsFrame(destination)) {
    if (auto resource = DataURL(verdict.redirect)) {
      Serve(client, resource->first, resource->second);
      return;
    }
  }
  client.OnComplete(network::URLLoaderCompletionStatus(net::ERR_BLOCKED_BY_CLIENT));
}

// One request the filter let through, between its client and the loader that
// serves it. Each redirect it is about to follow is checked as the request it
// becomes, so an address that redirects to a blocked one fails there. It
// lives on the filter sequence and goes away when the page lets go of the
// request or the loader that serves it has said all it will.
class FilteringLoader final : public network::mojom::URLLoader, public network::mojom::URLLoaderClient {
 public:
  static void Start(network::mojom::URLLoaderFactory& target,
                    mojo::PendingReceiver<network::mojom::URLLoader> loader,
                    int32_t request_id,
                    uint32_t options,
                    const network::ResourceRequest& request,
                    mojo::PendingRemote<network::mojom::URLLoaderClient> client,
                    const net::MutableNetworkTrafficAnnotationTag& annotation,
                    scoped_refptr<PageFilter> page,
                    std::string top) {
    auto* filtering = new FilteringLoader(std::move(loader), std::move(client), request, std::move(page), std::move(top));
    target.CreateLoaderAndStart(filtering->target_loader_.BindNewPipeAndPassReceiver(), request_id, options, request,
                                filtering->target_client_.BindNewPipeAndPassRemote(), annotation);
    // The loader that serves the request may close its pipe before its
    // client pipe delivers the completion, so only the client pipe's end,
    // after everything it carried, ends the request on that side.
    filtering->target_client_.set_disconnect_handler(
        base::BindOnce(&FilteringLoader::Gone, base::Unretained(filtering)));
  }

  FilteringLoader(const FilteringLoader&) = delete;
  FilteringLoader& operator=(const FilteringLoader&) = delete;

  // network::mojom::URLLoader:
  void FollowRedirect(network::HttpRequestHeadersUpdateParams headers_update_params,
                      const std::optional<GURL>& new_url) override {
    target_loader_->FollowRedirect(std::move(headers_update_params), new_url);
  }

  void SetPriority(net::RequestPriority priority, int32_t intra_priority_value) override {
    target_loader_->SetPriority(priority, intra_priority_value);
  }

  // network::mojom::URLLoaderClient:
  void OnReceiveEarlyHints(network::mojom::EarlyHintsPtr early_hints) override {
    client_->OnReceiveEarlyHints(std::move(early_hints));
  }

  void OnReceiveResponse(network::mojom::URLResponseHeadPtr head,
                         mojo::ScopedDataPipeConsumerHandle body,
                         std::optional<mojo_base::BigBuffer> cached_metadata) override {
    client_->OnReceiveResponse(std::move(head), std::move(body), std::move(cached_metadata));
  }

  void OnReceiveRedirect(const net::RedirectInfo& redirect_info, network::mojom::URLResponseHeadPtr head) override {
    asked_.url = redirect_info.new_url;
    asked_.method = redirect_info.new_method;
    const Verdict verdict = Decide(asked_, *page_, top_);
    if (verdict.verdict != CREST_CONTENT_FILTER_ALLOW) {
      Refuse(*client_, verdict, asked_.destination);
      Gone();
      return;
    }
    client_->OnReceiveRedirect(redirect_info, std::move(head));
  }

  void OnUploadProgress(int64_t current_position, int64_t total_size, OnUploadProgressCallback callback) override {
    client_->OnUploadProgress(current_position, total_size, std::move(callback));
  }

  void OnTransferSizeUpdated(int32_t transfer_size_diff) override {
    client_->OnTransferSizeUpdated(transfer_size_diff);
  }

  void OnComplete(const network::URLLoaderCompletionStatus& status) override { client_->OnComplete(status); }

 private:
  FilteringLoader(mojo::PendingReceiver<network::mojom::URLLoader> loader,
                  mojo::PendingRemote<network::mojom::URLLoaderClient> client,
                  const network::ResourceRequest& request,
                  scoped_refptr<PageFilter> page,
                  std::string top)
      : loader_receiver_(this, std::move(loader)),
        client_(std::move(client)),
        asked_{request.url, request.method, request.destination, request.request_initiator},
        page_(std::move(page)),
        top_(std::move(top)) {
    loader_receiver_.set_disconnect_handler(base::BindOnce(&FilteringLoader::Gone, base::Unretained(this)));
  }

  ~FilteringLoader() override = default;

  void Gone() { delete this; }

  mojo::Receiver<network::mojom::URLLoader> loader_receiver_;
  mojo::Remote<network::mojom::URLLoaderClient> client_;
  mojo::Remote<network::mojom::URLLoader> target_loader_;
  mojo::Receiver<network::mojom::URLLoaderClient> target_client_{this};
  Asked asked_;
  const scoped_refptr<PageFilter> page_;
  const std::string top_;
};

// A factory in front of the one a page's document or frame navigation would
// use, which fails each request the content filter blocks and hands the rest
// on unchanged. It lives on the filter sequence and goes away with its last
// pipe.
class FilteringFactory final : public network::mojom::URLLoaderFactory {
 public:
  static void Start(mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver,
                    mojo::PendingRemote<network::mojom::URLLoaderFactory> target,
                    scoped_refptr<PageFilter> page,
                    std::string top) {
    new FilteringFactory(std::move(receiver), std::move(target), std::move(page), std::move(top));
  }

  FilteringFactory(const FilteringFactory&) = delete;
  FilteringFactory& operator=(const FilteringFactory&) = delete;

  void CreateLoaderAndStart(mojo::PendingReceiver<network::mojom::URLLoader> loader,
                            int32_t request_id,
                            uint32_t options,
                            const network::ResourceRequest& request,
                            mojo::PendingRemote<network::mojom::URLLoaderClient> client,
                            const net::MutableNetworkTrafficAnnotationTag& annotation) override {
    const Asked asked{request.url, request.method, request.destination, request.request_initiator};
    const Verdict verdict = Decide(asked, *page_, top_);
    if (verdict.verdict != CREST_CONTENT_FILTER_ALLOW) {
      mojo::Remote<network::mojom::URLLoaderClient> refused(std::move(client));
      Refuse(*refused, verdict, request.destination);
      return;
    }
    // A request whose redirects could be blocked passes through a loader
    // that checks each of them; the rest go straight on.
    if (page_->Blocks() && KindOf(request.destination)) {
      FilteringLoader::Start(*target_, std::move(loader), request_id, options, request, std::move(client), annotation,
                             page_, top_);
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
                   scoped_refptr<PageFilter> page,
                   std::string top)
      : target_(std::move(target)), page_(std::move(page)), top_(std::move(top)) {
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

  mojo::ReceiverSet<network::mojom::URLLoaderFactory> receivers_;
  mojo::Remote<network::mojom::URLLoaderFactory> target_;
  const scoped_refptr<PageFilter> page_;
  const std::string top_;
};

// The top-level page a factory's requests belong to: the top frame of the
// document it serves, or for a frame's navigation, the page around the frame.
std::string TopLevelURL(content::RenderFrameHost* frame, const net::IsolationInfo& isolation_info) {
  std::optional<url::Origin> top = isolation_info.top_frame_origin();
  if (!top && frame->GetParentOrOuterDocument()) top = frame->GetOutermostMainFrame()->GetLastCommittedOrigin();
  if (!top) return {};
  const GURL url = top->GetTupleOrPrecursorTupleIfOpaque().GetURL();
  return url.is_valid() ? url.spec() : std::string();
}

}  // namespace

void FilterRequests(content::RenderFrameHost* frame,
                    content::ContentBrowserClient::URLLoaderFactoryType type,
                    const net::IsolationInfo& isolation_info,
                    network::URLLoaderFactoryBuilder& builder) {
  using Type = content::ContentBrowserClient::URLLoaderFactoryType;
  if (!IsEnabled() || !frame || (type != Type::kDocumentSubResource && type != Type::kNavigation)) return;
  EnginePage* page = EngineBinding::Get().PageFor(content::WebContents::FromRenderFrameHost(frame));
  if (!page) return;
  std::string top = TopLevelURL(frame, isolation_info);
  auto [receiver, target] = builder.Append();
  FilterSequence()->PostTask(FROM_HERE, base::BindOnce(&FilteringFactory::Start, std::move(receiver),
                                                       std::move(target), page->RequestFilter(), std::move(top)));
}

void UseContentFilter(uint64_t app) {
  if (Filter().check.load()) return;
  // The core's library exports them: the slot's address through the app, the
  // check every request goes through, and the release of a redirect it hands.
  auto slot_address = reinterpret_cast<SlotAddress>(dlsym(RTLD_DEFAULT, "crest_app_content_filter_slot"));
  auto check = reinterpret_cast<SlotCheck>(dlsym(RTLD_DEFAULT, "crest_content_filter_slot_check_redirect"));
  auto free = reinterpret_cast<BufferFree>(dlsym(RTLD_DEFAULT, "crest_content_filter_buffer_free"));
  void* slot = nullptr;
  if (!slot_address || !check || !free || slot_address(app, &slot) != CREST_OK || !slot) return;
  Filter().slot.store(static_cast<const crest_content_filter_slot_t*>(slot));
  Filter().free.store(free);
  Filter().check.store(check);
}

}  // namespace crest

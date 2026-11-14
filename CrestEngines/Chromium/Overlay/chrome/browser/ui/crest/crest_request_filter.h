#ifndef CHROME_BROWSER_UI_CREST_CREST_REQUEST_FILTER_H_
#define CHROME_BROWSER_UI_CREST_CREST_REQUEST_FILTER_H_

#include <atomic>
#include <cstdint>

#include "base/memory/ref_counted.h"
#include "content/public/browser/content_browser_client.h"

namespace content {
class RenderFrameHost;
}

namespace net {
class IsolationInfo;
}

namespace network {
class URLLoaderFactoryBuilder;
}

namespace crest {

// Whether a page blocks ads and trackers in the document it shows. The core
// decides once per navigation, on the UI thread; the request filter reads it
// on its own sequence.
class PageFilter final : public base::RefCountedThreadSafe<PageFilter> {
 public:
  PageFilter() = default;
  PageFilter(const PageFilter&) = delete;
  PageFilter& operator=(const PageFilter&) = delete;

  void SetBlocks(bool blocks) { blocks_.store(blocks, std::memory_order_relaxed); }
  bool Blocks() const { return blocks_.load(std::memory_order_relaxed); }

 private:
  friend class base::RefCountedThreadSafe<PageFilter>;
  ~PageFilter() = default;

  std::atomic<bool> blocks_{false};
};

// Puts Crest's request filter in front of the factory `builder` makes for a
// Crest page's document or for a navigation of one of its frames. Each request
// the core's content filter blocks fails with ERR_BLOCKED_BY_CLIENT, and one it
// redirects to a replacement resource is answered with that resource; each
// redirect a request it allows is about to follow is checked the same way. The
// filter judges each request as part of the top-level page, which
// `isolation_info` names for a document's requests. The check runs on a
// sequence of its own, through the core's slot, without the core's locks or
// managed code; a top-level document is never blocked. Factories for anything
// but a Crest page are left alone.
void FilterRequests(content::RenderFrameHost* frame,
                    content::ContentBrowserClient::URLLoaderFactoryType type,
                    const net::IsolationInfo& isolation_info,
                    network::URLLoaderFactoryBuilder& builder);

// Finds the core's content filter for `app`, once: the slot's address, which
// the core answers, and the check its library exports. Until it is found, or
// while the core has no filter in force, every request goes through.
void UseContentFilter(uint64_t app);

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_REQUEST_FILTER_H_

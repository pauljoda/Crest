#ifndef SERVICES_NETWORK_CREST_REQUEST_POLICY_H_
#define SERVICES_NETWORK_CREST_REQUEST_POLICY_H_

class GURL;

namespace net {
class URLRequest;
}

namespace network::crest {

// Whether Crest keeps `request`, about to load `url`, from reaching Google.
//
// Pages and the person may load anything. The browser's own requests reach a
// Google-owned host only for the services Crest keeps, each named by its
// traffic annotation and the hosts it uses. Any other browser request to
// Google fails, including one a later Chromium adds: the list fails closed.
// ForkMaintenance.md describes the review each milestone needs.
bool BlocksRequest(const net::URLRequest& request, const GURL& url);

}  // namespace network::crest

#endif  // SERVICES_NETWORK_CREST_REQUEST_POLICY_H_

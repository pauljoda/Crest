#include "services/network/crest_request_policy.h"

#include <algorithm>
#include <string>
#include <string_view>

#include "base/logging.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "net/url_request/url_request.h"
#include "services/network/public/mojom/network_context.mojom.h"
#include "services/network/url_loader.h"
#include "url/gurl.h"

namespace network::crest {

namespace {

using Annotation = net::internal::StringLiteralToHash;

// Requests a page or the person directs, wherever they go: navigations and
// their preloads, workers, downloads, developer tools, and the network's own
// work for a page's connection, such as its certificate, DNS and proxy.
constexpr Annotation kDirected[] = {
    "background_fetch_context",
    "bidirectional_stream",
    "blink_extension_resource_loader",
    "blink_fetch_later_manager",
    "blink_resource_loader",
    "certificate_verifier_2qwac_loader",
    "certificate_verifier_url_loader",
    "certificate_verifier_url_request",
    "dbsc_registration",
    "devtools_cdp_network_resource",
    "devtools_network_resource",
    "dns_over_https",
    "dns_transaction",
    "dom_distiller",
    "download_bubble_retry_download",
    "download_manager_resume",
    "download_web_contents_frame",
    "downloads_api_run_async",
    "drag_download_file",
    "early_hints_preload",
    "favicon_loader",
    "keepalive_fetch_retry",
    "navigation_url_loader",
    "parallel_download_job",
    "payment_manifest_downloader",
    "pdf_plugin_placeholder",
    "predictive_prefetch",
    "preload_activation_beacon",
    "proxy_config_direct",
    "proxy_config_settings",
    "proxy_config_system",
    "render_view_context_menu",
    "renderer_initiated_download",
    "reporting",
    "save_file_manager",
    "service_worker_navigation_preload",
    "service_worker_race_network_request",
    "service_worker_script_load",
    "service_worker_update_checker",
    "sigined_exchange_cert_fetcher",
    "speculation_rules_prefetch",
    "speculation_rules_prefetch_probe",
    "ssl_name_mismatch_lookup",
    "web_app_origin_association_download",
    "web_install_manifest_fetcher",
    "webauthn_rp_id_check",
    "websocket_basic_stream",
    "websocket_stream",
    "well_known_path_that_should_not_exist",
    "worker_script_load",
};

// A Google service Crest keeps, and the hosts it reaches. A host matches
// itself and its subdomains.
struct Service {
  Annotation annotation;
  std::string_view host;
};

constexpr Service kServices[] = {
    // Component updates: the certificate revocation list, Certificate
    // Transparency logs and root store, file types for download warnings,
    // and Widevine. The check names each component and its version and
    // carries no client identifier; packages download from Google's CDN.
    {"update_client", "update.googleapis.com"},
    {"update_client", "dl.google.com"},
    {"update_client", "gvt1.com"},
    // Extension updates and Chrome Web Store packages: update checks name
    // each extension and its version, and packages download from the store.
    {"extension_manifest_fetcher", "clients2.google.com"},
    {"extension_crx_fetcher", "clients2.google.com"},
    {"extension_crx_fetcher", "clients2.googleusercontent.com"},
    {"extension_crx_fetcher", "gvt1.com"},
    {"update_client", "clients2.google.com"},
    {"update_client", "clients2.googleusercontent.com"},
    {"content_hash_verification_job", "clients2.google.com"},
    {"content_hash_verification_job", "clients2.googleusercontent.com"},
    {"crest_web_store_download", "clients2.google.com"},
    {"crest_web_store_download", "clients2.googleusercontent.com"},
    {"crest_web_store_download", "gvt1.com"},
};

// Registrable names Google operates, under any public suffix: google.com
// and google.co.uk alike.
constexpr std::string_view kGoogleNames[] = {
    "1e100",       "android",           "app-measurement",  "appspot",
    "chrome",      "chromium",          "crashlytics",      "doubleclick",
    "firebaseio",  "g",                 "ggpht",            "gmail",
    "goo",         "google",            "google-analytics", "googleadservices",
    "googleapis",  "googlesyndication", "googletagmanager", "googletagservices",
    "googleusercontent", "googlevideo", "googlezip",        "gstatic",
    "gvt1",        "gvt2",              "gvt3",             "recaptcha",
    "withgoogle",  "youtube",           "youtube-nocookie", "ytimg",
};

bool IsGoogleHost(std::string_view host) {
  const std::string domain = net::registry_controlled_domains::GetDomainAndRegistry(
      host, net::registry_controlled_domains::EXCLUDE_PRIVATE_REGISTRIES);
  const size_t dot = domain.find('.');
  if (dot == std::string::npos) {
    return false;
  }
  const std::string_view name = std::string_view(domain).substr(0, dot);
  const std::string_view registry = std::string_view(domain).substr(dot + 1);
  return registry == "google" || registry == "goog" || std::ranges::contains(kGoogleNames, name);
}

bool Matches(std::string_view host, std::string_view service) {
  return host == service ||
         (host.ends_with(service) && host[host.size() - service.size() - 1] == '.');
}

}  // namespace

bool BlocksRequest(const net::URLRequest& request, const GURL& url) {
  if (!url.SchemeIsHTTPOrHTTPS() && !url.SchemeIsWSOrWSS()) {
    return false;
  }
  const std::string_view host = url.host();
  if (!IsGoogleHost(host)) {
    return false;
  }
  // A renderer's request belongs to a page, a worker or an extension.
  if (const URLLoader* loader = URLLoader::ForRequest(request);
      loader && loader->GetProcessId() != mojom::kBrowserProcessId) {
    return false;
  }
  const int32_t annotation = request.traffic_annotation().unique_id_hash_code;
  if (std::ranges::contains(kDirected, annotation, &Annotation::hash_value)) {
    return false;
  }
  for (const Service& service : kServices) {
    if (service.annotation.hash_value == annotation && Matches(host, service.host)) {
      return false;
    }
  }
  VLOG(1) << "Crest blocked a browser request to " << host << " (annotation " << annotation << ")";
  return true;
}

}  // namespace network::crest

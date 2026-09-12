# Native resource and extension panel privacy review

Reviewed September 12, 2026 against `dd0cd812` and the 0.5.109 cleanup in this
commit, on system WebKit: macOS 27.0 (26A428), Xcode 27.0 (27A266a).
This is a scoped source review and isolated runtime validation, not a security
certification of the entire browser or installed extensions.

## Original findings

The retained Codex Security scan `a0a1f2f7-398f-43b7-8423-0dda27c9b492`
examined snapshot `a95f221704a12017d996ca60b1d136ab2ab15453`. Its coverage
was partial and its findings were source-only. The request captures below are
new evidence from synthetic fixtures, not claims about that original scan.

| Concern | Final handling and evidence | Disposition |
| --- | --- | --- |
| `csf_261bb8122c0f84720e466a94`: parent host-only cookies exported to child hosts | Favicon capture exports no cookies. Same-origin authenticated requests run in the live page's isolated JavaScript world with WebKit's own store. Other origins use an ephemeral native session with no cookie or credential store. Actual requests verify host-only, path, cross-site and Space boundaries. | Original disclosure path removed. |
| `csf_7d2c1539c6729f7c17fbc4fd`: full page URL copied into Referer | Both capture paths omit Referer. WebKit fetch explicitly sets an empty referrer and `no-referrer`; native requests never receive the page URL as a header and strip sensitive headers on redirects. Wire tests cover document/element no-referrer and origin policies, icons, manifests, manifest icons, and redirect responses that try to set `unsafe-url`. | Original disclosure path removed. |
| URL credentials, fragments and downgrade disclosure | Native resource URLs remove userinfo and fragments, reject credential challenges, and repeat sanitization on redirects. WebKit capture uses no referrer and same-origin credentials. HTTPS-to-HTTP fixtures show no leaked referrer or cookies. | Verified within these capture paths. |
| Response-size check after full download | Both paths consume streamed bodies and stop at the limit: 128 KiB for icons and 1 MiB for manifests. A slow oversized response is rejected before its server finishes streaming. | Full-body buffering removed from Crest's loaders. This is an application body limit, not a bound on all WebKit/Foundation process memory. |
| Authenticated favicon and Microsoft rendering compatibility | A cookie-protected manifest and redirected icon still load through WebKit. Retained tests cover Microsoft CDN discovery, SVG rasterization, manifest candidate selection and rejecting login HTML returned as an icon. | Synthetic compatibility coverage passes; an authenticated Microsoft site was not wire-captured. |

The platform fixture sets cookies through actual HTTP responses. On this system,
WebKit exports a parent host-only cookie as `parent.localhost`, and an explicit
Domain cookie as `.parent.localhost`. These attributes and the requests received
by the loopback server are attached to the test result. No conclusion depends on
Foundation normalizing a full-page Referer: that header is never constructed.
WebKit can still emit the normal CORS `Origin` header on a cross-origin redirect;
the captured value contains only the origin, with no page path or query.
`no-referrer` controls Referer, not that separate [Fetch protocol header](https://fetch.spec.whatwg.org/#origin-header).
Secure-cookie downgrade assertions account for WebKit's special treatment of
trustworthy localhost; native fallback and cross-origin downgrade requests must
still carry no cookies.

The shared capture implementation serves both macOS and iOS. macOS additionally
retries discovery for late page metadata; retries enter the same protected path.
The unloaded-tab fallback removes the page path/query/userinfo/fragment when
constructing `/favicon.ico`, and scopes its cache to the profile.

## Extension compatibility boundary

Ordinary tabs, authentication pages and native extension APIs remain on their
Space's WebKit store. Each side-panel document has its own nonpersistent store.
A direct, non-redirected extension iframe navigation can activate only a currently
permitted HTTPS origin. Only matching Secure, explicit Lax/Strict source cookies
are copied; copies retain domain/host-only, path and expiry and become HttpOnly
SameSite=None. None, unspecified, insecure and partitioned cookies are excluded.
Content rules limit where copies can be sent. Foreign website frames cannot
navigate into a protected origin or fetch it with those cookies.

This is the intentional, bounded compatibility exception requested for system
WebKit. It relaxes SameSite inside the panel; it does not preserve every browser
cookie restriction unchanged or implement Chrome's engine exception exactly.
See [the policy, wire comparison and compatibility limits](ExtensionCompatibility.md#cookies-for-sites-an-extension-frames).
Chrome documents its network-only host-permission exception in
[Storage and cookies](https://developer.chrome.com/docs/extensions/develop/concepts/storage-and-cookies).

Source-cookie removal/expiry, permission changes after activation, panel close,
Space locking and runtime removal tear down panel sessions. The normal store is
never updated from panel responses. Native extension storage and background
messaging remain owned by the extension context. Required isolation SPI is checked
and unsupported configurations refuse panel navigation; system WebKit updates
still require rerunning these integration tests.

The review found and fixed one additional ownership bug: a retained panel's delayed
external navigation used the newly selected Space's generic tab opener. It now
uses the panel's owning Space and the existing Space-aware navigation path. A real
WebKit panel regression failed before the repair and passes afterward.

## Cleanup and retained protection

- Removed the duplicate cross-origin HTTP server from the hosted-content tests;
  those tests now use the shared loopback fixture. CSP and foreign-extension
  script/CSS isolation assertions are retained.
- Renamed the deletion-only cookie helper to `includesCookieDomainForRemoval`,
  documented its deliberately broader deletion scope, and corrected the obsolete
  test name claiming it described cookie visibility. It has no request call sites.
- Kept the legacy hosted-store identifier solely for site-data/profile deletion.
  Removing it would strand old storage; new panels never open that store.
- Confirmed the old Space-wide cookie-copy service, its broker plumbing and the
  temporary sign-in/visual diagnostics are absent. Permanent fixtures that protect
  authorization, persistence, browser state and extension recovery remain.
- Added source-cookie expiry and delayed panel-link Space ownership coverage to
  the existing suites, without adding a separate test harness.

## Validation and remaining limits

The final macOS run completed **125 passed, 1 opt-in clipboard test skipped,
0 failed**. It includes favicon privacy/fallback/render safety, panel cookie wire
requests, hosted CSP/content isolation and background recovery, native controller
and storage behavior, sidebar state/navigation, private/profile isolation and
site-data removal. Both new regressions passed. The macOS and iOS Simulator builds, Swift formatting,
architecture checks and diff whitespace checks passed.

Local evidence: `/tmp/crest-security-cleanup-final-20260912.xcresult` contains
synthetic cookie representation and server-received request attachments. These
machine-local results are not committed; the retained fixtures reproduce them.
The selected XCTest classes are `BrowserFaviconPrivacyTests`,
`BrowserFaviconFallbackLoaderTests`, `BrowserFaviconRenderSafetyTests`,
`BrowserExtensionWebsiteDataTests`, `BrowserExtensionHostedContentIsolationTests`,
`BrowserExtensionControllerPoolTests`, `BrowserExtensionSidebarStoreTests`,
`BrowserExtensionStartupPipelineTests`, `BrowserWebsiteDataStoreTests`,
`BrowserProfileIsolationTests`, `BrowserExtensionHostedPageConfigurationPolicyTests`
and `BrowserExtensionSidebarNavigationPolicyTests` in the `Crest` macOS scheme.

The runtime evidence is from synthetic local requests. The user's successful
Claude/Cowork check and prior LastPass sign-in/save/fill/restart checks are separate
compatibility evidence; this review did not repeat a live account sign-in or send
a chat. Long-running token rotation and authenticated Microsoft favicon wire
capture remain unverified. Grant expiry has source review coverage; the new expiry
case specifically exercises a source cookie expiring after a real response.
Asynchronous WebKit notifications and teardown cannot retract requests already
in flight. Native public-resource fallback deliberately carries no authentication
when a cross-origin resource requires it.

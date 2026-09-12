# Cookie ownership and native-resource privacy review

Reviewed September 11–12, 2026. Source baseline: `6f53535b`, Crest `0.5.105`. The accompanying favicon patch advances the patch version to `0.5.106`. Tests ran against an isolated checkout of that baseline with the task changes, because unrelated test edits were in progress in the primary worktree.

**Recommendation:** WebKit should remain the sole owner of browser cookies and authenticated request construction. The favicon cookie bridge can be removed now and is removed in this patch. The extension-hosted cookie mirror is the main remaining architectural problem: it changes a request-specific permission into a shared, persistent cookie property. Runtime fixtures confirm both its compatibility benefit and failures in permission revocation, extension isolation, and partition identity. Removing it immediately would break some authenticated embedded sites; replacing it needs a separate compatibility migration.

This is a focused review of cookie storage, copying, automatic resource loading, and adjacent credential transports. It is not a certification of the whole browser, an exhaustive extension audit, or a claim that all supported OS versions behave identically.

## What owns credentials today

| Path | Current ownership | Assessment and action |
| --- | --- | --- |
| Ordinary Mac and mobile tabs | A profile-specific `WKWebsiteDataStore`; isolated launches use nonpersistent stores | Keep. WebKit selects cookies, applies SameSite, redirects, partitioning, and HTTP policy. Crest chooses the Space/store. |
| Favicons, manifests, manifest icons | Before this patch: exported WebKit cookies and an explicit full-page Referer on native requests | Remove the bridge. The patch uses WebKit for authenticated same-origin fetches and a credentialless native fallback for public resources. |
| Extension `cookies` API | Native WebKit extension implementation | Keep delegation. Do not build another cookie API or general cookie matcher. |
| Extension side panels/offscreen hosted sites | A second store per Space/profile; a bidirectional synchronizer strips SameSite in the hosted copy | Highest-priority follow-up. This is the remaining production cookie-copying subsystem. |
| `identity.launchWebAuthFlow` | A Crest-owned WebKit view using the requesting Space's ordinary store | Keep. OAuth provider sessions do not require copying cookies. Callback interception is separate from cookie ownership. |
| Downloads and retry | `WKDownload`, with a reconstructed request replayed in the original WebKit view and an assignment guard | Keep WebKit transport. A fixture found an authenticated retry compatibility gap, but no raw cookie/referrer replay leak. |
| HTTP Basic/Digest authentication | WebKit challenges; Crest supplies profile-scoped credentials and UI | Keep the narrow challenge adapter. It is not a cookie bridge. |
| Site-data clearing | WebKit cookie deletion and website-data removal; persistent profiles also clear the derived hosted store | Necessary ownership/lifecycle work. A deletion matcher must not be reused as a request-cookie matcher. Review ephemeral hosted-store cleanup during the extension migration. |
| Extension brokered WebSockets | An ephemeral Foundation session with cookie and credential storage disabled | Already avoids browser-cookie copying. Retain pending separate worker/socket compatibility work. |
| Search suggestions | Ephemeral Foundation session, cookies disabled, 64 KiB response limit | Generally appropriate. Explicitly disable credential storage and cancel the streaming task on early exit in a small follow-up. |
| Chrome Web Store update lookup | `URLSession.shared.data(from:)` | Unnecessary shared transport and unbounded response buffering. Use a bounded, public-resource session in a separate cleanup; no WebKit cookie export was found here. |

Relevant owners: [page configuration](../../CrestShared/Infrastructure/WebKit/PageConfiguration.swift), [website stores and clearing](../../CrestShared/Infrastructure/WebsiteData/WebsiteDataStore.swift), [hosted store](../../CrestShared/Infrastructure/Extensions/Compatibility/ExtensionHostedWebsiteDataStore.swift), [cookie coordinator](../../CrestMac/Infrastructure/WebKit/BrowserExtensions/BrowserExtensionCookieJarCoordinator.swift), [cookie access policy](../../CrestShared/Domain/BrowserExtensionServices/CookieAccess/BrowserExtensionCookieAccessPolicy.swift), [cookie access lifetime](../../CrestShared/Application/BrowserExtensionServices/CookieAccess/BrowserExtensionCookieAccessStore.swift), [frame permission gate](../../CrestMac/Infrastructure/WebKit/BrowserExtensions/BrowserExtensionFramedSiteCookieAccess.swift), [OAuth host](../../CrestMac/Infrastructure/WebKit/BrowserExtensions/BrowserExtensionWebAuthFlowHost.swift), [download retry](../../CrestShared/Infrastructure/Downloads/DownloadRetryContext.swift), [HTTP authentication](../../CrestShared/Application/BrowserAuthentication/BrowserHTTPAuthenticationSession.swift), [brokered WebSocket](../../CrestMac/Infrastructure/WebKit/BrowserExtensionBrokeredWebSocket.swift), [suggestions](../../CrestShared/Features/Chrome/Components/BrowserCommandPalette/Models/BrowserCommandPaletteModel.swift), and [update lookup](../../CrestShared/Infrastructure/Extensions/Sources/ChromeWebStore/ChromeWebStoreUpdateChecker.swift).

## Native-resource repair and wire evidence

The two retained findings, `csf_261bb8122c0f84720e466a94` and `csf_7d2c1539c6729f7c17fbc4fd`, were rechecked against current source. Their original scan baseline was `a95f221704a12017d996ca60b1d136ab2ab15453`; neither that scan nor APP-209 established these privacy boundaries. This review adds isolated request captures.

The former native loader used a broad suffix domain matcher, a simple path prefix, a cookie snapshot from the page's store, and `pageURL.absoluteString` as Referer. It downloaded entire bodies before enforcing byte limits. The same construction affected icons and manifests. A cookie-clearing helper's broad domain semantics were unsuitable for sending credentials.

| Controlled experiment | Before repair | After repair |
| --- | --- | --- |
| Parent sets a host-only HttpOnly cookie; page names a child-host icon | Child request contained the parent cookie | Child receives no parent host-only cookie |
| `/private` cookie; candidates use `/privateer/icon` and a redirect to `/public/icon` | Prefix matching and redirected native headers disclosed the path cookie | WebKit respects path boundaries; native requests carry no cookies |
| Page URL contains `?secret=query#fragment`; document uses `no-referrer` | Resource request contained the page URL including query and fragment | No Referer on icons, manifests, manifest icons, or their redirects |
| `origin` policy and per-element referrer policy; redirect responds with `Referrer-Policy: unsafe-url` | Native construction did not apply the effective browser policy | No Referer; redirects cannot expand an empty referrer source |
| HTTPS page, same-origin icon redirect to HTTP, plus direct public HTTP candidate | Previously depended on downstream handling | No downgrade referrer; insecure/public requests carry no cookies or Authorization |
| Different Space contains a second session cookie | Snapshot was Space-local, but the request matcher was unsafe | Live WebKit store remains Space-local; public native transport has no store |
| Cross-site redirect to a host with preexisting Lax/Strict cookies | Native code lacked browser SameSite context | Neither the WebKit fetch with `same-origin` credentials nor the public retry sends them |
| Authenticated same-origin manifest and icon, including redirects | Authentication worked through cookie forwarding | Authentication works through WebKit; no cookie export |
| Continuous oversized icon/manifest response | Full-response buffering preceded rejection | Both transports stop before EOF; icon cap 128 KiB, manifest cap 1 MiB |

On this platform, a real `Set-Cookie` without Domain returned from `WKHTTPCookieStore` as `domain=parent.localhost`. A Domain cookie returned as `.parent.localhost`. HttpOnly, Secure, path, and SameSite were present in the exported properties. An unspecified SameSite attribute returned as raw `none`. These are observed representations, not a new cross-version contract for Crest to emulate.

A separate Foundation loopback probe sent this synthetic header value:

```text
Referer: https://fixture-user:fixture-password@parent.localhost/private/page?secret=query#fragment
```

The receiver saw that value verbatim, including user information and fragment. Foundation did not sanitize an explicitly supplied header. A 131,073-byte response with delayed completion also made `data(for:)` wait about 5.01 seconds before returning the whole body. This closes the source findings' header-normalization and full-buffering proof gaps on the tested runtime.

The patch's [capture implementation](../../CrestShared/Infrastructure/Favicons/FaviconCapture.swift) fetches in WebKit's isolated client content world so page scripts cannot replace its `fetch`. Same-origin requests use `credentials: 'same-origin'`, `referrer: ''`, and `referrerPolicy: 'no-referrer'`. WebKit retains cookie and redirect decisions. The empty source remains empty even if a redirect advertises a less restrictive policy. Omitting a referrer is deliberately more restrictive than policies such as `origin`; no policy parser or synthetic origin header is needed. These request concepts are defined by the [Fetch standard](https://fetch.spec.whatwg.org/).

Cross-origin resources and unsuccessful WebKit fetches use the [public native loader](../../CrestShared/Infrastructure/Favicons/FaviconResourceLoader.swift). Its private ephemeral session has no cookie storage, credential storage, or cache. It strips URL user information/fragments, disables cookie handling, strips sensitive headers on every redirect, and declines non-server-trust authentication challenges. It streams into a capped buffer and cancels the task on exit. There is one native loading policy shared with the background fallback loader.

Manifest-relative icon URLs now resolve against the final manifest response URL. Existing browser-icon ranking, manifest purpose filtering, SVG rasterization, image caching, and profile cache leases remain in place.

Compatibility limits are explicit: authenticated cross-origin icons and servers that require a Referer may now fall back to another candidate. Credentialless cross-origin CDN icons without CORS still load. Same-origin cookie-authenticated fixtures pass. Existing Microsoft-style rendering fixtures pass, but no signed-in Microsoft account or enterprise authentication environment was exercised. App-level byte buffers are bounded; this is not a guarantee about all WebKit/CFNetwork internal buffering or decoded-image process memory.

## Extension mirror: confirmed problems

The hosted-store workaround does solve a real difference. Chrome documents a host-permission-dependent same-site exemption for extension network requests. Our native WebKit extension fixture withheld Strict and Lax cookies even with the relevant host permission; copying cookies unchanged into a separate store did not change that. Removing SameSite from the hosted copies did. [Chrome's documented behavior](https://developer.chrome.com/docs/extensions/develop/concepts/storage-and-cookies) and [WebKit issue 260676](https://bugs.webkit.org/show_bug.cgi?id=260676) provide relevant context; the latter concerns extension fetches, while the following measurements are our own iframe captures.

The architectural mismatch is visible in the storage graph:

```mermaid
flowchart LR
    Tabs[Ordinary tabs in Space A] --> Normal[WebKit normal store]
    Normal <-->|Bidirectional cookie copies| Sync[SameSite rewriting]
    Sync <--> Hosted[One hosted store for Space A]
    ExtensionA[Extension A with site permission] --> Hosted
    ExtensionB[Extension B without site permission] --> Hosted
```

The permission gate decides whether copying starts. It does not constrain subsequent cookie use in the shared store.

### 1. Revocation leaves authenticated embedded requests enabled

**Confirmed on the wire; high-priority authorization boundary.** After granting a host, loading an embedded site, denying that host permission, stopping synchronization, and removing observation, a new view using the retained hosted store still sent the relaxed Strict and Lax session cookies.

`revalidatePermissions`/`unregister` update host bookkeeping and stop observation. They do not remove or restore the cookies already copied. The hosted store is persistent for persistent profiles. Persistence makes restart exposure plausible from source, but this review did not run a full app restart or extension uninstall experiment.

### 2. Another extension receives the same relaxed session behavior

**Confirmed on the wire; high-priority extension isolation boundary.** A second actual `WKWebExtensionContext`, with no permission for the fixture host, framed that host using the same hosted store and sent all three session cookies, including those originally marked Strict and Lax.

This establishes authenticated request capability outside the granting extension's host permission. It does not establish JavaScript access to HttpOnly cookies, response-body access across origins, or a working account takeover. Consequences depend on the site's embedded behavior and other defenses. The ordinary tab store kept its original SameSite attributes throughout.

The captured Cookie headers were:

| Fixture stage | Header at the embedded host |
| --- | --- |
| Ordinary first-party request | `auditPartitioned=P; auditLax=L; auditLoose=U; auditStrict=S` |
| Native permitted extension iframe, normal store | `auditLoose=U` |
| Separate hosted store, unchanged cookie copies | `auditLoose=U` |
| After Crest's SameSite relaxation | `auditLax=L; auditLoose=U; auditStrict=S` |
| New view after revocation and synchronization shutdown | `auditLax=L; auditLoose=U; auditStrict=S` |
| Different extension with no permission for the host | `auditLax=L; auditLoose=U; auditStrict=S` |

All values were synthetic. Strict/Lax cookies were HttpOnly and Secure. Their emission in extension frames was measured over trustworthy localhost, where this WebKit build accepts Secure cookies even on HTTP.

### 3. Synchronization loses partition identity

**Confirmed store-level loss; security and compatibility concern.** Two `Partitioned` cookies with the same name, host, and path were seeded under different top-level sites. WebKit returned both:

```text
auditPartitioned=P, domain=parent.localhost, path=/,
  StoragePartition=http://parent.localhost
auditPartitioned=Q, domain=parent.localhost, path=/,
  StoragePartition=http://other.localhost
```

The synchronizer's `CookieKey` contains only name/domain/path; `sameCookie` also omits partition identity. A first synchronization into a fresh hosted store copied only P in this run. Which value survives depends on enumeration order. A separate experiment that pre-copied both cookies unchanged preserved both, showing that the loss occurred in Crest's dictionary projection.

There was no observed conversion into an unpartitioned cookie and no partitioned cookie was emitted by the extension iframe. The confirmed defect is identity collision and incomplete synchronization. Incorrect update/deletion attribution follows from the source model but was not separately driven to an account-level effect. Adding an undocumented raw key to the dictionary would address this one representation without making cookie rewriting a reliable browser-policy substitute.

### 4. Host-only eligibility is still too broad in the extension copier

**Confirmed from source; distinct from the repaired native disclosure.** `BrowserExtensionCookieAccessPolicy.appliesTo` strips the leading dot and accepts `host.hasSuffix("." + domain)` for both domain and host-only cookies. The comment claiming that host-only cookies match only their own host is false. Its existing test named `testHostOnlyCookieMatchesOnlyThatHost` actually expects a child host to match.

This can make permission for a child host select a parent's host-only cookie for copying/relaxation. WebKit still enforces that copied cookie's host-only scope on requests, so it is not evidence that WebKit sends the parent cookie directly to the child. It broadens the set of credentials present and weakened in the shared hosted store. Combined with the shared-store findings, copy eligibility is not a sufficient authorization boundary.

### 5. Lifetime and writeback add more policy state

**Source-backed follow-up, not separately exploited.** Registrations live at extension-client/Space scope, rather than the lifetime of the particular framed document. Normal and hosted jars each have snapshots, observers, a debounce, write suppression, conflict resolution, and remembered original attributes. A hosted cookie with no ordinary-store counterpart has no original SameSite provenance to restore during writeback. Site-data clearing explicitly discovers the persistent hosted store but has no equivalent identifier for an ephemeral hosted store; correctness there depends on active synchronization and lifecycle cleanup.

The ordinary-store precedence and attribute-preservation tests are useful, but they test the mechanics of the mirror. They do not prove that the mirror preserves browser authorization semantics.

## How far delegation can go

The favicon change removes an entire unnecessary credential boundary without losing same-origin authenticated discovery. Ordinary navigation, OAuth, native extension cookie APIs, and regular downloads already have appropriate WebKit ownership. Keep these paths small and resist creating a universal Foundation client that reconstructs browser cookies, SameSite, partition keys, or Referer policy.

For extension-hosted sites, the desired capability is a WebKit decision scoped to the requesting extension, current host permission, frame/request, Space, and top-level partition. A permanent mutation of shared cookies cannot faithfully express that capability. No supported embedder API providing that exact exemption was identified in the SDK/source review. This is an API investigation result, not proof that no future WebKit version can provide one.

Storage Access API is worth validating with representative sites, but it is not a drop-in SameSite bypass: WebKit documents user activation and per-page access rules, and sites must participate. Globally allowing third-party cookies also does not express an extension/host permission boundary. [WebKit's Storage Access API documentation](https://webkit.org/blog/11545/updates-to-the-storage-access-api/) and [tracking prevention guidance](https://webkit.org/tracking-prevention/) describe those separate controls.

| Order | Concrete follow-up | Completion evidence |
| --- | --- | --- |
| 1 | Land the scoped favicon repair | Retained request-capture tests, rendering checks, and platform validation below |
| 2 | Replace the Space-wide extension SameSite exemption with an extension/permission-scoped design | A revoked extension and an unpermitted peer cannot make the fixture send previously restricted cookies; ordinary tabs remain protected |
| 3 | Prototype native WebKit hosting and supported access mechanisms against the actual extensions/sites that need the workaround | Record which authenticated operations require embedding, which work through normal tabs/OAuth, and which require an upstream WebKit change |
| 4 | If temporary cookie copies remain, isolate their store and lifetime, implement revocation teardown before reuse, and define partition/domain/writeback ownership | Wire tests for domain cookies, redirects to other hosts, peer extensions, revocation, partitioned cookies, logout, restart, Space changes, and deletion; merely using one store per extension is insufficient |
| 5 | Migrate and delete the derived persistent jars when the mirror is retired | Old relaxed cookies cannot reappear after upgrade/restart; all live views release old stores |
| 6 | Harden the small public native clients and investigate download retry context loss | Bounded update responses; explicit credentialless suggestion transport; authenticated download retry works without exported Cookie headers |

The compatibility decision for an unfixable embedded flow should be explicit: use a normal site tab/auth flow, or offer a narrowly described compatibility exception with proven boundaries. Do not silently make the ordinary store more permissive. The current patch leaves extension behavior unchanged; the confirmed extension findings remain open.

## Download and authentication checks

A real WebKit navigation with `no-referrer` downloaded an attachment after a parent-to-child redirect. The initial parent request carried the appropriate cookies; the child received the domain cookie and no parent host-only cookie. No Referer was emitted. `WKDownload.originalRequest` exposed the final child URL and ordinary public request headers, but no Cookie or Referer.

Replaying through the existing request-reconstruction helper in the same view sent no cookies. Fresh `URLRequest` retries, both with and without a `mainDocumentURL`, also sent no cookies in this fixture. This suggests a WebKit download-start context/compatibility limitation, not proof that Crest's copied header dictionary leaks a session. Preserve WebKit transport and reproduce against authenticated real downloads before changing retry behavior. POST bodies, HTTP-auth challenges, and every redirect shape were not covered by this probe.

HTTP authentication policy review found profile-scoped credential access, secure-origin restrictions for stored credentials, exact protection-space matching, and transient challenge credentials. Existing authentication policy tests were included in final verification. OAuth uses the ordinary Space store directly and intercepts its callback URL; a live provider login was outside this review.

## Validation, reproducibility, and limits

Environment: macOS 27.0 build `26A428`, Xcode 27.0 build `27A266a`, and iOS 27.0 simulator. These are the installed runtimes, not all supported shipping platforms.

The retained [five privacy tests](../../CrestTests/BrowserFaviconPrivacyTests.swift) run at the shared owner on macOS. They use real `NWListener` HTTP/TLS requests with `parent.localhost`, `child.parent.localhost`, and `other.localhost`; separate nonpersistent WebKit stores represent Spaces. HTML fixtures disable WebKit's independent automatic manifest loader with `manifest-src 'none'`, so captured manifest requests measure Crest's fetch paths. A short-lived TLS identity is generated during the test and imported only into memory. Trust handling is restricted to the local fixture host/port. No certificate or private key is committed or trusted system-wide.

Supplemental iOS execution ran the same five privacy scenarios successfully. The built test app alone received ATS exceptions for the loopback fixture hosts, because shipping iOS policy blocks those native HTTP requests. Shipping configuration was not weakened. Temporary iOS test/resource wiring was removed after the run; shared Mac coverage remains permanent.

The extension experiment used a temporary Manifest V2 extension with permission for the parent host, a second extension without that permission, real WebKit controllers/configurations, and the production hosted-store assignment and synchronizer. Reproduction stages are recorded in the wire table above. Partition P was set with the parent as top-level site; Q was set by the parent iframe under the other top-level site. A fresh coordinator/store then exercised the first copy. Temporary audit methods and fixtures were removed after recording results; the existing cookie mechanics tests remain. Regression coverage for the newly discovered extension boundaries belongs with their eventual repair.

During streaming validation, one WebKit build withheld a short response tail until EOF after delivering the first 1 MiB. A JS timing probe isolated this behavior; the permanent test uses a continuous chunked response and verifies early cancellation instead. This resembles a documented WebKit streaming regression, but equivalence to that bug was not established. A 12-second abort also bounds stalled fetches. [WebKit issue 322545](https://bugs.webkit.org/show_bug.cgi?id=322545).

Local result bundles and transcripts preserve the synthetic captures:

| Artifact under `/tmp` | Evidence |
| --- | --- |
| `crest-favicon-before.xcresult` | Pre-repair cookie/referrer failures and WebKit cookie representation attachments |
| `crest-favicon-foundation-probe-results.txt` | Literal userinfo/query/fragment Referer and delayed full-body Foundation load |
| `crest-favicon-ios-wire.xcresult` | Five passing supplemental iOS privacy scenarios |
| `crest-cookie-partition-probe.xcresult` and `.log` | Extension stages, revocation/peer request captures, two source partitions and one fresh copied partition |
| `crest-cookie-final-probes.xcresult` and `.log` | Download retry captures and expanded extension audit |
| `crest-cookie-final-validation-v2.xcresult` | Final retained tests after temporary probe cleanup |

These are local evidence artifacts, not committed fixtures or permanent download links. The tables preserve the meaningful observations if temporary results are later removed. Final macOS verification passed **94 tests, zero failures**: 25 favicon tests (including the five retained privacy cases), 39 cookie access/coordinator/frame-gate tests, and 30 authentication/hosted-content/profile-isolation tests. The supplemental iOS privacy run passed **five tests, zero failures**. Swift formatting for all five task Swift files, version metadata, public-source hygiene, architecture checks, and whitespace checks passed. The broader vertical-organization check reports two existing baseline violations in `View+BrowserFolderHeaderLayout.swift` and `BrowserRootView.swift`; neither file is changed by this task. Passing current cookie mechanics tests does not close the extension findings.

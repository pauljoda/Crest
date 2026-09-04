import Foundation

/// The cookie rewrite that stands in for Chrome's "an extension page is
/// first-party for a site it has host permission for" rule.
///
/// WebKit relaxes third-party *blocking* for extension web views, but
/// `SameSite` is decided in WebCore from the registrable domain of the top
/// document. An extension page framing `https://claude.ai/` is therefore
/// cross-site to WebCore, and every `SameSite=Lax`/`Strict` cookie the site
/// owns is withheld — from the frame navigation and from every request that
/// frame's document makes afterwards. There is no embedder seam for the
/// decision, so Crest changes the only thing it owns: the cookies themselves.
///
/// These are pure functions over `HTTPCookie` so the rule can be read and
/// tested without a website data store. Nothing here decides *whether* a host
/// is eligible; that is the store's job.
enum BrowserExtensionCookieAccessPolicy {
    /// Foundation publishes no `HTTPCookiePropertyKey` for `HttpOnly`, but it
    /// both reads and writes the raw key, so a rewrite can preserve the flag.
    static let httpOnlyPropertyKey = HTTPCookiePropertyKey("HttpOnly")

    /// The cookie host a framed URL names, or `nil` for anything that has no
    /// cookie jar of its own.
    ///
    /// Only `http` and `https` qualify. An extension page frames plenty that
    /// is not a site — `about:blank`, its own `chrome-extension://` resources,
    /// `blob:` and `data:` documents — and none of those can be first-party
    /// for a site's cookies.
    static func host(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard let host = normalized(url.host() ?? ""), !host.isEmpty else { return nil }
        return host
    }

    /// Whether `cookie` is one a request to `host` would carry.
    ///
    /// RFC 6265 domain matching: the cookie applies when its domain equals the
    /// host or the host is a subdomain of it. Foundation does not report
    /// whether a cookie was stored host-only, and WebKit's conversion keeps a
    /// domain cookie's leading dot only some of the time, so the dot is
    /// stripped and both forms are matched the same way. A host-only cookie's
    /// domain is exactly its host, so it still matches only that host — and a
    /// cookie for `sub.example.com` is correctly not matched for
    /// `example.com`, which would never be sent it.
    static func appliesTo(cookie: HTTPCookie, host: String) -> Bool {
        guard let domain = normalized(cookie.domain), let host = normalized(host) else {
            return false
        }
        return domain == host || host.hasSuffix(".\(domain)")
    }

    /// Whether this cookie is one a cross-site request would be denied.
    ///
    /// Only `Lax` and `Strict` restrict anything. Everything else — no
    /// attribute at all, or the `none` WebKit reports for an unspecified one
    /// when a cookie comes back out of `WKHTTPCookieStore` — is already sent
    /// cross-site, because WebKit does not apply Chromium's Lax-by-default.
    ///
    /// This distinction is what stops a rewrite pass from writing its own
    /// output back forever: after one pass every matching cookie reads as
    /// `none`, nothing more is written, and the cookie-store observer that
    /// each write wakes finally goes quiet.
    static func restrictsCrossSiteUse(_ cookie: HTTPCookie) -> Bool {
        guard let policy = cookie.sameSitePolicy?.rawValue.lowercased() else { return false }
        return policy == HTTPCookieStringPolicy.sameSiteLax.rawValue.lowercased()
            || policy == HTTPCookieStringPolicy.sameSiteStrict.rawValue.lowercased()
    }

    /// A copy of `cookie` with no `SameSite` attribute, or `nil` when the
    /// cookie already places no cross-site restriction.
    ///
    /// Everything else is carried across unchanged. `maximumAge` is dropped in
    /// favour of the absolute date the cookie already resolved, because
    /// `HTTPCookie` re-bases a relative age against the moment of
    /// construction: keeping it would quietly extend the cookie's life on
    /// every rewrite.
    static func relaxed(_ cookie: HTTPCookie) -> HTTPCookie? {
        guard restrictsCrossSiteUse(cookie), var properties = cookie.properties else { return nil }
        properties.removeValue(forKey: .sameSitePolicy)
        properties.removeValue(forKey: .maximumAge)
        if let expiresDate = cookie.expiresDate {
            properties[.expires] = expiresDate
        } else {
            properties.removeValue(forKey: .expires)
        }
        // Re-assert the two flags Foundation exposes as properties only when
        // they were set, so a cookie whose dictionary omitted them still comes
        // back secure and script-invisible.
        if cookie.isSecure { properties[.secure] = "TRUE" }
        if cookie.isHTTPOnly { properties[httpOnlyPropertyKey] = "TRUE" }
        return HTTPCookie(properties: properties)
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: ". \t")
        )
        return trimmed.isEmpty ? nil : trimmed
    }
}

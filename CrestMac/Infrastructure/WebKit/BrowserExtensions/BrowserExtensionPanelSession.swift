import Foundation
import WebKit

/// A short-lived compatibility session for one extension panel. The browser's
/// store remains authoritative; nothing in this store is copied back to it.
/// WebKit sends cookies, enforces their scope and referrer policy, and strips
/// credentials outside the explicitly activated HTTPS origins.
@MainActor
final class BrowserExtensionPanelSession: NSObject, WKHTTPCookieStoreObserver {
    let websiteDataStore = WKWebsiteDataStore.nonPersistent()
    private let normal: WKWebsiteDataStore
    private let context: WKWebExtensionContext
    private let content: WKUserContentController
    // WebKit registers the configuration controller with every extension.
    // Keep it separate from the per-document controller used for isolation.
    // Initial frame requests consult this controller before the override lands.
    private let navigationContent = WKUserContentController()
    private let ruleStore = WKContentRuleListStore.default()!
    private let observer = BrowserExtensionContextObserver()
    private var ruleList: WKContentRuleList?
    private var navigationRules: WKContentRuleList?
    private var origins: [String: URL] = [:]
    private var originals: [CookieKey: HTTPCookie] = [:]
    private var pending: Task<Bool, Never>?
    private var expiry: Task<Void, Never>?
    private var active = true
    var invalidate: (() -> Void)?

    private struct CookieKey: Hashable {
        let name: String
        let domain: String
        let path: String
        init(_ cookie: HTTPCookie) {
            name = cookie.name
            domain = cookie.domain
            path = cookie.path
        }
    }

    init?(configuration: BrowserExtensionPageConfiguration, content: WKUserContentController) {
        let selector = NSSelectorFromString("_setRelatedWebView:")
        guard configuration.webViewConfiguration.responds(to: selector) else { return nil }
        normal = configuration.webViewConfiguration.websiteDataStore
        context = configuration.context
        self.content = content
        super.init()
        // Related web views must use the same store. Keep native extension IPC,
        // but detach the background view's process relationship before switching.
        configuration.webViewConfiguration.perform(selector, with: nil)
        configuration.webViewConfiguration.websiteDataStore = websiteDataStore
        configuration.webViewConfiguration.userContentController = navigationContent
        // This context belongs only to its regular Space. Actual private windows
        // use a separate pool which loads no extensions. WebKit needs this flag
        // to run the owner's native APIs in this nonpersistent panel store.
        context.hasAccessToPrivateData = true
        observer.observe(
            context, permissionsDidChange: { [weak self] in self?.checkPermissions() },
            runtimeSummaryDidChange: {})
        normal.httpCookieStore.add(self)
    }

    isolated deinit { stop() }

    func prepare() async -> Bool {
        do {
            try await installNavigationRules()
            try await installRules()
            return active
        } catch {
            stop()
            return false
        }
    }

    func allows(_ action: WKNavigationAction) async -> Bool {
        guard active, let url = action.request.url else { return false }
        guard action.targetFrame?.isMainFrame == false else { return true }
        guard url.user == nil, url.password == nil else { return false }
        guard let origin = Self.origin(url) else { return true }
        let source = action.sourceFrame.securityOrigin
        let fromExtension = source.protocol == context.baseURL.scheme && source.host == context.baseURL.host
        let sourceOrigin = "\(source.protocol)://\(source.host):\(source.port == 0 ? 443 : source.port)"
        // A foreign ancestor must not acquire a protected document, even if it
        // navigates back to an already permitted origin. Content rules alone do
        // not protect that navigation: WebKit can match the *new* frame URL.
        if context.hasAccess(to: url), !fromExtension, sourceOrigin != origin { return false }
        guard fromExtension, context.hasAccess(to: url), origins[origin] == nil else { return true }
        // A redirect is not a fresh extension request to activate another site.
        let redirect = NSSelectorFromString("_isRedirect")
        guard action.responds(to: redirect), (action.value(forKey: "_isRedirect") as? Bool) == false else {
            return false
        }
        let predecessor = pending
        let task = Task { @MainActor [weak self] in
            _ = await predecessor?.value
            guard let self, active, context.hasAccess(to: url) else { return false }
            origins[origin] = url
            do {
                try await installRules()
                guard active, context.hasAccess(to: url) else { return false }
                await synchronize()
                return active
            } catch {
                invalidate?()
                stop()
                return false
            }
        }
        pending = task
        return await task.value
    }

    private func installRules() async throws {
        var rules: [[String: Any]] = [
            ["trigger": ["url-filter": ".*"], "action": ["type": "block-cookies"]]
        ]
        let owner = "^" + NSRegularExpression.escapedPattern(for: context.baseURL.absoluteString)
        for url in origins.values {
            let pattern =
                "^https://" + NSRegularExpression.escapedPattern(for: url.host()!)
                + ((url.port == nil || url.port == 443) ? "(:443)?" : ":\(url.port!)") + "/"
            rules.append([
                "trigger": ["url-filter": pattern, "if-frame-url": [owner, pattern]],
                "action": ["type": "ignore-previous-rules"],
            ])
        }
        let identifier = "crest-panel-session-\(UUID())"
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
        let compiled = try await ruleStore.compileContentRuleList(
            forIdentifier: identifier, encodedContentRuleList: encoded)
        guard active, let compiled else {
            try? await ruleStore.removeContentRuleList(forIdentifier: identifier)
            return
        }
        let previous = ruleList
        content.add(compiled)
        ruleList = compiled
        if let previous {
            content.remove(previous)
            try? await ruleStore.removeContentRuleList(forIdentifier: previous.identifier)
        }
    }

    private func installNavigationRules() async throws {
        var rules: [[String: Any]] = [
            ["trigger": ["url-filter": ".*"], "action": ["type": "block-cookies"]]
        ]
        for (pattern, expiration) in context.grantedPermissionMatchPatterns where expiration > Date() {
            guard pattern.matchesAllURLs || pattern.scheme == "https" || pattern.scheme == "*" else { continue }
            let host = pattern.host ?? "*"
            let hostFilter: String
            if host == "*" {
                hostFilter = "[^/:]+"
            } else if host.hasPrefix("*.") {
                hostFilter = "([^/:]+\\.)?" + NSRegularExpression.escapedPattern(for: String(host.dropFirst(2)))
            } else {
                hostFilter = NSRegularExpression.escapedPattern(for: host)
            }
            rules.append([
                "trigger": ["url-filter": "^https://" + hostFilter + "(:[0-9]+)?/", "resource-type": ["document"]],
                "action": ["type": "ignore-previous-rules"],
            ])
        }
        let identifier = "crest-panel-navigation-\(UUID())"
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
        let compiled = try await ruleStore.compileContentRuleList(
            forIdentifier: identifier, encodedContentRuleList: encoded)
        guard active, let compiled else {
            try? await ruleStore.removeContentRuleList(forIdentifier: identifier)
            return
        }
        navigationContent.add(compiled)
        navigationRules = compiled
    }

    private static func origin(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(),
            url.user == nil, url.password == nil
        else { return nil }
        return "https://\(host):\(url.port ?? 443)"
    }

    private func isEligible(_ cookie: HTTPCookie) -> Bool {
        guard cookie.isSecure, cookie.properties?[HTTPCookiePropertyKey("StoragePartition")] == nil,
            cookie.expiresDate.map({ $0 > Date() }) ?? true
        else { return false }
        let domain = cookie.domain.lowercased()
        return origins.values.contains { url in
            guard context.hasAccess(to: url), let host = url.host()?.lowercased() else { return false }
            if domain.hasPrefix(".") {
                let suffix = String(domain.dropFirst())
                return host == suffix || host.hasSuffix("." + suffix)
            }
            return host == domain
        }
    }

    private func embeddedCopy(_ cookie: HTTPCookie) -> HTTPCookie {
        guard cookie.sameSitePolicy == .sameSiteLax || cookie.sameSitePolicy == .sameSiteStrict,
            var properties = cookie.properties
        else { return cookie }
        properties[.sameSitePolicy] = "None"
        // Chrome's network exception does not expose Lax/Strict through
        // document.cookie. Make the compatibility copy stricter for scripts.
        properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        properties.removeValue(forKey: .maximumAge)
        properties[.expires] = cookie.expiresDate
        return HTTPCookie(properties: properties) ?? cookie
    }

    private func isSourceCookie(_ cookie: HTTPCookie) -> Bool {
        // Older WebKit releases erase partition metadata when exporting cookies.
        // CHIPS requires SameSite=None in WebKit. Copy only explicit Lax/Strict
        // cookies, so missing metadata cannot turn a partition into a shared jar.
        isEligible(cookie) && (cookie.sameSitePolicy == .sameSiteLax || cookie.sameSitePolicy == .sameSiteStrict)
    }

    private func synchronize() async {
        guard active else { return }
        let cookies = await normal.httpCookieStore.allCookies()
        guard active else { return }
        let current = Dictionary(
            cookies.filter(isSourceCookie).map { (CookieKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        // A first-party logout or clear-site-data discards the entire temporary
        // session, including local response cookies and DOM storage.
        if originals.keys.contains(where: { current[$0] == nil }) {
            invalidate?()
            stop()
            return
        }
        for (key, cookie) in current {
            guard active else { return }
            if originals[key]?.properties as NSDictionary? != cookie.properties as NSDictionary? {
                await websiteDataStore.httpCookieStore.setCookie(embeddedCopy(cookie))
            }
        }
        originals = current
        scheduleExpiry()
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            guard let self, active else { return }
            let predecessor = pending
            pending = Task { @MainActor [weak self] in
                _ = await predecessor?.value
                guard let self, active else { return false }
                await synchronize()
                return active
            }
        }
    }

    private func checkPermissions() {
        if !origins.isEmpty {
            invalidate?()
            stop()
        }
    }

    private func scheduleExpiry() {
        expiry?.cancel()
        let deadlines =
            Array(context.grantedPermissionMatchPatterns.values) + originals.values.compactMap(\.expiresDate)
        guard let date = deadlines.min(), date != .distantFuture else { return }
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.invalidate?()
            self?.stop()
        }
    }

    func stop() {
        guard active else { return }
        active = false
        pending?.cancel()
        expiry?.cancel()
        observer.stopObservingAll()
        normal.httpCookieStore.remove(self)
        originals.removeAll()
        origins.removeAll()
        let rules = ruleList
        let initialRules = navigationRules
        ruleList = nil
        navigationRules = nil
        let store = websiteDataStore
        Task { @MainActor [ruleStore] in
            await store.httpCookieStore.setCookiePolicy(.disallow)
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            if let rules { try? await ruleStore.removeContentRuleList(forIdentifier: rules.identifier) }
            if let initialRules { try? await ruleStore.removeContentRuleList(forIdentifier: initialRules.identifier) }
        }
    }
}

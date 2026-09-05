import Foundation
import WebKit
import os

/// Synchronizes a Space's normal and hosted cookie jars. SameSite relaxation
/// is confined to the hosted jar; refreshing a session there never strips the
/// protection from the normal jar. Normal-tab changes win simultaneous writes.
@MainActor
final class BrowserExtensionCookieJarCoordinator: BrowserExtensionCookieJarRelaxing {
    typealias WebsiteDataStoreProvider = @MainActor (SpaceID) -> WKWebsiteDataStore?
    typealias HostedStoreFactory = @MainActor (WKWebsiteDataStore, SpaceID) -> WKWebsiteDataStore

    private struct CookieKey: Hashable {
        let name: String
        let domain: String
        let path: String
        init(_ cookie: HTTPCookie) {
            name = cookie.name
            domain = cookie.domain.lowercased()
            path = cookie.path
        }
    }

    private final class StorePair {
        let normal: WKWebsiteDataStore
        let hosted: WKWebsiteDataStore
        var previousNormal: [CookieKey: HTTPCookie] = [:]
        var previousHosted: [CookieKey: HTTPCookie] = [:]
        var initializedHosts: Set<String> = []
        var synchronizedHosts: Set<String>?
        var observations: [BrowserExtensionCookieJarObservation] = []
        var pendingPass: Task<Void, Never>?
        var passID: UUID?
        var isActive = true

        init(normal: WKWebsiteDataStore, hosted: WKWebsiteDataStore) {
            self.normal = normal
            self.hosted = hosted
        }
    }

    private let websiteDataStore: WebsiteDataStoreProvider
    private let makeHostedStore: HostedStoreFactory
    private let coalescingDelay: Duration
    private var stores: [SpaceID: StorePair] = [:]

    init(
        coalescingDelay: Duration = .milliseconds(150),
        makeHostedStore: @escaping HostedStoreFactory = BrowserExtensionHostedWebsiteDataStore.make,
        websiteDataStore: @escaping WebsiteDataStoreProvider
    ) {
        self.coalescingDelay = coalescingDelay
        self.makeHostedStore = makeHostedStore
        self.websiteDataStore = websiteDataStore
    }

    func hostedWebsiteDataStore(in spaceID: SpaceID) -> WKWebsiteDataStore? {
        storePair(in: spaceID)?.hosted
    }

    func setSynchronizedHosts(_ hosts: Set<String>, in spaceID: SpaceID) {
        storePair(in: spaceID)?.synchronizedHosts = hosts
    }

    private func storePair(in spaceID: SpaceID) -> StorePair? {
        if let existing = stores[spaceID] { return existing }
        guard let normal = websiteDataStore(spaceID) else { return nil }
        let pair = StorePair(normal: normal, hosted: makeHostedStore(normal, spaceID))
        precondition(pair.normal !== pair.hosted, "Hosted cookie relaxation needs its own store")
        stores[spaceID] = pair
        return pair
    }

    func relax(host: String, in spaceID: SpaceID) async {
        guard let pair = storePair(in: spaceID) else { return }
        let predecessor = pair.pendingPass
        let passID = UUID()
        let task = Task { @MainActor [weak self] in
            await predecessor?.value
            guard let self, pair.isActive else { return }
            await synchronize(host: host, pair: pair)
        }
        pair.passID = passID
        pair.pendingPass = task
        await task.value
        if pair.passID == passID {
            pair.pendingPass = nil
            pair.passID = nil
        }
    }

    private func synchronize(host: String, pair: StorePair) async {
        guard pair.isActive, pair.synchronizedHosts?.contains(host) != false else { return }
        for observation in pair.observations { observation.beginApplying() }
        defer { for observation in pair.observations { observation.endApplying() } }
        let normalStore = pair.normal.httpCookieStore
        let hostedStore = pair.hosted.httpCookieStore
        let normal = await matchingCookies(in: normalStore, host: host)
        let hosted = await matchingCookies(in: hostedStore, host: host)
        let isInitialCopy = !pair.initializedHosts.contains(host)
        let previousKeys = pair.previousNormal.filter {
            BrowserExtensionCookieAccessPolicy.appliesTo(cookie: $0.value, host: host)
        }.keys
        let previousHostedKeys = pair.previousHosted.filter {
            BrowserExtensionCookieAccessPolicy.appliesTo(cookie: $0.value, host: host)
        }.keys
        let keys = Set(normal.keys).union(hosted.keys).union(previousKeys).union(previousHostedKeys)

        for key in keys {
            guard pair.isActive, pair.synchronizedHosts?.contains(host) != false else { return }
            let source = normal[key]
            let embedded = hosted[key]
            let sourceChanged = !sameCookie(source, pair.previousNormal[key])
            let hostedChanged = !sameCookie(embedded, pair.previousHosted[key])
            if isInitialCopy || sourceChanged {
                if let source {
                    let copy = BrowserExtensionCookieAccessPolicy.relaxed(source) ?? source
                    if !sameCookie(copy, embedded) { await hostedStore.setCookie(copy) }
                    pair.previousHosted[key] = copy
                } else {
                    if let embedded { await hostedStore.deleteCookie(embedded) }
                    pair.previousHosted[key] = nil
                }
                pair.previousNormal[key] = source
            } else if hostedChanged {
                if let embedded {
                    let original = BrowserExtensionCookieAccessPolicy.normalCookie(embedded, preserving: source)
                    if !sameCookie(original, source) { await normalStore.setCookie(original) }
                    let relaxed = BrowserExtensionCookieAccessPolicy.relaxed(embedded) ?? embedded
                    if !sameCookie(relaxed, embedded) { await hostedStore.setCookie(relaxed) }
                    pair.previousNormal[key] = original
                    pair.previousHosted[key] = relaxed
                } else {
                    if let source { await normalStore.deleteCookie(source) }
                    pair.previousNormal[key] = nil
                    pair.previousHosted[key] = nil
                }
            }
        }
        // Remember only values this pass actually synchronized. Reading a final
        // snapshot here could swallow a site's concurrent write before copying
        // it to the other jar; the observer must see that as a fresh change.
        pair.initializedHosts.insert(host)
    }

    private func matchingCookies(in store: WKHTTPCookieStore, host: String) async -> [CookieKey: HTTPCookie] {
        Dictionary(
            (await store.allCookies()).filter {
                BrowserExtensionCookieAccessPolicy.appliesTo(cookie: $0, host: host)
            }.map { (CookieKey($0), $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func sameCookie(_ left: HTTPCookie?, _ right: HTTPCookie?) -> Bool {
        guard let left, let right else { return left == nil && right == nil }
        return left.name == right.name && left.domain == right.domain && left.path == right.path
            && left.value == right.value && left.expiresDate == right.expiresDate
            && left.isSecure == right.isSecure && left.isHTTPOnly == right.isHTTPOnly
            && sameSiteValue(left) == sameSiteValue(right) && left.portList == right.portList
    }

    private func sameSiteValue(_ cookie: HTTPCookie) -> String {
        cookie.sameSitePolicy?.rawValue.lowercased() ?? "none"
    }

    func observe(spaceID: SpaceID, onChange: (@MainActor () -> Void)?) {
        guard let onChange else {
            if let pair = stores.removeValue(forKey: spaceID) {
                pair.isActive = false
                for observation in pair.observations { observation.stop() }
            }
            return
        }
        guard let pair = storePair(in: spaceID) else { return }
        if !pair.observations.isEmpty {
            for observation in pair.observations { observation.onChange = onChange }
            return
        }
        pair.observations = [pair.normal, pair.hosted].map {
            BrowserExtensionCookieJarObservation(
                cookieStore: $0.httpCookieStore,
                coalescingDelay: coalescingDelay, onChange: onChange)
        }
        for observation in pair.observations { observation.start() }
    }
}

/// One Space's `WKHTTPCookieStoreObserver`, with the debounce and the
/// self-write suppression that keep it from chasing its own tail.
@MainActor
private final class BrowserExtensionCookieJarObservation: NSObject, WKHTTPCookieStoreObserver {
    var onChange: (@MainActor () -> Void)?

    private let cookieStore: WKHTTPCookieStore
    private let coalescingDelay: Duration
    private var pendingPass: Task<Void, Never>?
    private var applyingDepth = 0
    private var didChangeWhileApplying = false

    init(
        cookieStore: WKHTTPCookieStore,
        coalescingDelay: Duration,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.cookieStore = cookieStore
        self.coalescingDelay = coalescingDelay
        self.onChange = onChange
        super.init()
    }

    func start() {
        cookieStore.add(self)
    }

    func stop() {
        pendingPass?.cancel()
        pendingPass = nil
        onChange = nil
        cookieStore.remove(self)
    }

    func beginApplying() {
        applyingDepth += 1
    }

    /// Ends one rewrite pass, and re-reads once if the site wrote while it ran.
    ///
    /// Dropping those notifications outright would lose exactly the write this
    /// whole mechanism exists for — the response that establishes a session.
    /// The extra pass converges: a second rewrite of an already-relaxed cookie
    /// writes nothing and notifies no one.
    func endApplying() {
        applyingDepth = max(0, applyingDepth - 1)
        guard applyingDepth == 0, didChangeWhileApplying else { return }
        didChangeWhileApplying = false
        schedulePass()
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            self?.noteCookiesDidChange()
        }
    }

    private func noteCookiesDidChange() {
        guard applyingDepth == 0 else {
            didChangeWhileApplying = true
            return
        }
        schedulePass()
    }

    private func schedulePass() {
        pendingPass?.cancel()
        let coalescingDelay = coalescingDelay
        pendingPass = Task { @MainActor [weak self] in
            try? await Task.sleep(for: coalescingDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingPass = nil
            self.onChange?()
        }
    }
}

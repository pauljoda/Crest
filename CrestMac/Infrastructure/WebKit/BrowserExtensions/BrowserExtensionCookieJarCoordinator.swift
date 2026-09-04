import Foundation
import WebKit
import os

/// Applies `BrowserExtensionCookieAccessPolicy` to one Space's real cookie
/// jar, and keeps applying it while an extension still frames the site.
///
/// The jar is resolved per Space from the extension controller's own
/// `defaultWebsiteDataStore` — the same object the extension web views were
/// configured with — rather than rebuilt from the profile. A rewrite that
/// landed in a different store would be invisible to the frame it was meant
/// for, and this way a Space with no loaded extension controller resolves to
/// nothing and is left alone.
@MainActor
final class BrowserExtensionCookieJarCoordinator: BrowserExtensionCookieJarRelaxing {
    typealias WebsiteDataStoreProvider = @MainActor (SpaceID) -> WKWebsiteDataStore?

    private static let log = Logger(
        subsystem: ProductIdentity.serviceNamespace,
        category: "extension-cookie-access"
    )

    private let websiteDataStore: WebsiteDataStoreProvider
    private let coalescingDelay: Duration
    private var observations: [SpaceID: BrowserExtensionCookieJarObservation] = [:]

    init(
        coalescingDelay: Duration = .milliseconds(150),
        websiteDataStore: @escaping WebsiteDataStoreProvider
    ) {
        self.coalescingDelay = coalescingDelay
        self.websiteDataStore = websiteDataStore
    }

    func relax(host: String, in spaceID: SpaceID) async {
        guard let cookieStore = websiteDataStore(spaceID)?.httpCookieStore else { return }
        let observation = observations[spaceID]
        // Our own writes wake the observer. Suppressing them here is what
        // keeps a login from costing a burst of passes; anything the site
        // wrote during the window is remembered and re-read once.
        observation?.beginApplying()
        defer { observation?.endApplying() }
        let cookies = await cookieStore.allCookies()
        var rewritten = 0
        for cookie in cookies
        where BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: host) {
            // `relaxed` answers nil for a cookie that already carries no
            // `SameSite`, which is what stops a rewrite pass from writing —
            // and therefore from notifying — anything at all.
            guard let relaxed = BrowserExtensionCookieAccessPolicy.relaxed(cookie) else { continue }
            await cookieStore.setCookie(relaxed)
            rewritten += 1
        }
        guard rewritten > 0 else { return }
        // The host and a count, never a cookie name or value: enough to tell a
        // frame that was never relaxed from one whose jar had nothing to fix.
        Self.log.info(
            "relaxed SameSite on \(rewritten, privacy: .public) cookie(s) for \(host, privacy: .public)"
        )
    }

    func observe(spaceID: SpaceID, onChange: (@MainActor () -> Void)?) {
        guard let onChange else {
            observations.removeValue(forKey: spaceID)?.stop()
            return
        }
        if let existing = observations[spaceID] {
            existing.onChange = onChange
            return
        }
        guard let cookieStore = websiteDataStore(spaceID)?.httpCookieStore else { return }
        let observation = BrowserExtensionCookieJarObservation(
            cookieStore: cookieStore,
            coalescingDelay: coalescingDelay,
            onChange: onChange
        )
        observations[spaceID] = observation
        observation.start()
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

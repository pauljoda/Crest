#if CREST_CHROMIUM_HOST
import AppKit
import Observation

/// Owns the WebContents behind the original Crest page card. The shell and
/// portable session retain their tab identities; this object owns only a page.
@Observable @MainActor
final class ChromiumNativePage: BrowserPageEngine {
    let id = UUID().uuidString
    let surface = ChromiumNativePageView()
    var isPrivateBrowsing = false
    private let profileID: UUID
    var observer: (String, [String: Any]) -> Void
    private var host: (any CrestChromiumEngineHost)?
    private var requestedURL: URL?
    private var zoom: CGFloat = 1
    private var creating = false
    private var created = false
    private var disposed = false

    init(profileID: UUID, observer: @escaping (String, [String: Any]) -> Void = { _, _ in }) {
        self.profileID = profileID
        self.observer = observer
        surface.page = self
    }

    var nativeView: NSView { surface }
    private(set) var backHistory: [BrowserNavigationHistoryItem] = []
    private(set) var forwardHistory: [BrowserNavigationHistoryItem] = []
    func mediaActivity() async -> BrowserPageMediaActivity? {
        guard created, !disposed, let values = host?.mediaActivity(forPage: id) else { return nil }
        return BrowserPageMediaActivity(isPlaying: values["playing"] as? Bool == true,
            isCapturing: values["capturing"] as? Bool == true,
            hasPictureInPicture: values["pictureInPicture"] as? Bool == true)
    }
    func transferOwnership(to windowID: BrowserWindowID) -> Bool {
        guard created, !disposed, let host else { return false }
        return host.preparePage(id, forWindow: windowID.rawValue.uuidString)
    }

    func capture(rect: CGRect?, width: CGFloat?, completion: @escaping @MainActor (NSImage?) -> Void) {
        guard created, !disposed, let host else { completion(nil); return }
        host.capturePage(id, rect: rect ?? .zero, width: width ?? 0) { image in
            MainActor.assumeIsolated { completion(image) }
        }
    }
    func load(_ request: URLRequest) {
        guard let url = request.url else { return }
        load(url)
    }
    func navigateHistory(by offset: Int) {
        guard created, !disposed, offset != 0 else { return }
        _ = host?.command("engine.history", page: id, url: String(offset))
    }
    func reload(bypassingCache: Bool) {
        command(bypassingCache ? "engine.reload_from_origin" : "engine.reload")
    }
    func stop() { command("engine.stop") }

    func load(_ url: URL) {
        requestedURL = url
        if created { navigatePendingURL() }
        else { attachIfPossible() }
    }

    func attachIfPossible() {
        guard !disposed, let windowID = surface.window?.identifier?.rawValue,
            let host = CrestChromiumRoot.engineHost else { return }
        self.host = host
        if created {
            guard host.preparePage(id, forWindow: windowID), let view = host.view(forPage: id) else { return }
            if view.superview !== surface {
                view.removeFromSuperview()
                view.frame = surface.bounds
                view.autoresizingMask = [.width, .height]
                surface.addSubview(view)
            }
            host.didAttachPage(id, window: windowID)
            return
        }
        guard !creating else { return }
        let sourceProfile = isPrivateBrowsing ? CrestChromiumRoot.privateSourceProfileID : nil
        guard !isPrivateBrowsing || sourceProfile != nil else { observer("creation_failed", [:]); return }
        creating = true
        if !host.createPage(id, profile: profileID.uuidString, window: windowID,
            privateMode: isPrivateBrowsing, sourceProfile: sourceProfile?.uuidString, observer: { [weak self] event, values in
                MainActor.assumeIsolated { self?.receive(event, values: values) }
            }) {
            creating = false
            observer("creation_failed", [:])
        }
    }

    func adopt(_ token: String) -> Bool {
        guard !created, !creating, !disposed, let host = CrestChromiumRoot.engineHost else { return false }
        self.host = host
        creating = true
        let accepted = host.adoptPage(token, asPage: id, profile: profileID.uuidString) { [weak self] event, values in
            MainActor.assumeIsolated { self?.receive(event, values: values) }
        }
        if !accepted { creating = false }
        return accepted
    }

    func performFind(_ query: String, configuration: BrowserFindConfiguration,
                     completion: @escaping @MainActor (Bool) -> Void) {
        guard created, !disposed, let host,
            host.find(inPage: id, query: query, backwards: configuration.backwards,
                caseSensitive: configuration.caseSensitive, completion: { found in
                    MainActor.assumeIsolated { completion(found) }
                }) else { completion(false); return }
    }

    struct SitePermission: Identifiable {
        let id: String
        let label: String
        var value: Int
        let supportsAsk: Bool
    }
    var permissions: [SitePermission] {
        (host?.permissions(forPage: id) ?? []).compactMap { item in
            guard let id = item["id"] as? String, let label = item["label"] as? String,
                let value = item["value"] as? Int else { return nil }
            return SitePermission(id: id, label: label, value: value, supportsAsk: item["supportsAsk"] as? Bool ?? false)
        }
    }
    func setPermission(_ permission: String, value: Int) -> Bool {
        host?.setPermission(permission, page: id, value: value) ?? false
    }

    struct ExtensionAction: Identifiable {
        let id: String
        let name: String
        let badge: String
        let icon: NSImage?
        let pinned: Bool
    }

    var extensions: [ExtensionAction] {
        guard created, !disposed else { return [] }
        return (host?.extensions(forPage: id) ?? []).compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            return ExtensionAction(id: id, name: name, badge: item["badge"] as? String ?? "", icon: item["icon"] as? NSImage, pinned: item["pinned"] as? Bool ?? false)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func runExtension(_ extensionID: String, anchor: BrowserExtensionPopupAnchor? = nil) {
        guard created, !disposed else { return }
        let anchor = anchor ?? BrowserExtensionPopupAnchor(screenPoint: NSEvent.mouseLocation, sourceWindow: surface.window)
        guard let source = anchor.presentationSource(fallbackWindow: surface.window) else { return }
        if host?.runExtension(extensionID, page: id, anchorView: source.view, anchorRect: source.rect) != true {
            CrestChromiumRoot.showNativeNotice("This extension action is unavailable on this page.", icon: "puzzlepiece.extension")
        }
    }

    static func webStoreExtensionID(_ url: URL?) -> String? {
        guard let url, url.scheme == "https", url.host == "chromewebstore.google.com",
            url.pathComponents.count >= 3, url.pathComponents[1] == "detail",
            let id = url.pathComponents.last, id.count == 32,
            id.allSatisfy({ ("a"..."p").contains(String($0)) }) else { return nil }
        return id
    }

    func setZoom(_ zoom: CGFloat) {
        self.zoom = zoom
        if created { _ = host?.command("engine.zoom", page: id, url: String(Double(zoom))) }
    }

    func detach() { if created { host?.didDetachPage(id) } }

    func command(_ command: String) {
        guard created, !disposed else { return }
        _ = host?.command(command, page: id, url: nil)
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        surface.subviews.forEach { $0.removeFromSuperview() }
        host?.disposePages([id], windows: [], releaseProfiles: [])
        host = nil
    }

    private func navigatePendingURL() {
        guard let requestedURL else { return }
        self.requestedURL = nil
        _ = host?.command("engine.navigate", page: id, url: ChromiumInternalURL.engine(requestedURL.absoluteString))
    }

    private func history(_ value: Any?) -> [BrowserNavigationHistoryItem] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let depth = item["depth"] as? Int, depth > 0,
                let rawURL = item["url"] as? String,
                let url = URL(string: ChromiumInternalURL.presented(rawURL)) else { return nil }
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return BrowserNavigationHistoryItem(depth: depth,
                title: title.isEmpty ? url.host() ?? url.absoluteString : title, url: url)
        }
    }

    private func receive(_ event: String, values: [String: Any]) {
        guard !disposed else { return }
        if event == "changed" {
            backHistory = history(values["backHistory"])
            forwardHistory = history(values["forwardHistory"])
        }
        if event == "created" {
            created = true
            creating = false
            attachIfPossible()
            setZoom(zoom)
            navigatePendingURL()
        } else if event == "creation_failed" {
            creating = false
        }
        observer(event, ChromiumInternalURL.presentedValues(values))
    }
}

@MainActor
final class ChromiumNativePageView: NSView, BrowserNativePageSurfaceLifecycle {
    weak var page: ChromiumNativePage?
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        guard let view = subviews.first else { return super.becomeFirstResponder() }
        return window?.makeFirstResponder(view) ?? false
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { page?.attachIfPossible() } else { page?.detach() }
    }
    func didAttach(to host: BrowserWebHostView) { page?.attachIfPossible() }
    func willDetach(from host: BrowserWebHostView) { page?.detach() }
}
#endif

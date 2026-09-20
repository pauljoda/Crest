#if CREST_CHROMIUM_HOST
import AppKit

/// Owns the WebContents behind the original Crest page card. The shell and
/// portable session retain their tab identities; this object owns only a page.
@MainActor
final class ChromiumNativePage {
    let id = UUID().uuidString
    let surface = ChromiumNativePageView()
    var isPrivateBrowsing = false
    private let profileID: UUID
    private let observer: (String, [String: Any]) -> Void
    private var host: (any CrestChromiumEngineHost)?
    private var requestedURL: URL?
    private var creating = false
    private var created = false
    private var disposed = false

    init(profileID: UUID, observer: @escaping (String, [String: Any]) -> Void) {
        self.profileID = profileID
        self.observer = observer
        surface.page = self
    }

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
        // Private windows are not registered in this first host. Never fall
        // through to a persistent Chromium profile for a private page.
        guard !isPrivateBrowsing else { observer("creation_failed", [:]); return }
        creating = true
        if !host.createPage(id, profile: profileID.uuidString, window: windowID,
            privateMode: false, sourceProfile: nil, observer: { [weak self] event, values in
                MainActor.assumeIsolated { self?.receive(event, values: values) }
            }) {
            creating = false
            observer("creation_failed", [:])
        }
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
        _ = host?.command("engine.navigate", page: id, url: requestedURL.absoluteString)
    }

    private func receive(_ event: String, values: [String: Any]) {
        guard !disposed else { return }
        if event == "created" {
            created = true
            creating = false
            attachIfPossible()
            navigatePendingURL()
        } else if event == "creation_failed" {
            creating = false
        }
        observer(event, values)
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

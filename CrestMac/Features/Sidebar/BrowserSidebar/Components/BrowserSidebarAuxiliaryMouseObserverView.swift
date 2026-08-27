import AppKit
import WebKit

@MainActor
final class BrowserSidebarAuxiliaryMouseObserverView: NSView {
    var perform: @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void
    private var eventMonitor: Any?

    init(
        perform: @escaping @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void
    ) {
        self.perform = perform
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateEventMonitor()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func stopMonitoring() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func updateEventMonitor() {
        stopMonitoring()
        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseDown
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        guard
            let action = BrowserSidebarMouseButtonPolicy.action(
                for: event.buttonNumber
            )
        else { return event }

        let webView = webViewUnderPointer(for: event)
        guard
            let disposition = BrowserSidebarMouseButtonPolicy.disposition(
                for: action,
                pointerScope: pointerScope(for: event, webView: webView),
                canNavigatePage: canNavigate(action, in: webView)
            )
        else { return event }

        execute(disposition, in: webView)
        return nil
    }

    private func pointerScope(
        for event: NSEvent,
        webView: WKWebView?
    ) -> BrowserSidebarMousePointerScope {
        if webView != nil { return .webpage }
        guard !isHidden else { return .unowned }
        let location = convert(event.locationInWindow, from: nil)
        return bounds.contains(location) ? .sidebar : .unowned
    }

    private func canNavigate(
        _ action: BrowserSidebarMouseButtonAction,
        in webView: WKWebView?
    ) -> Bool {
        guard let webView else { return false }
        return switch action {
        case .previousSpace:
            webView.canGoBack
        case .nextSpace:
            webView.canGoForward
        }
    }

    private func execute(
        _ disposition: BrowserSidebarMouseButtonDisposition,
        in webView: WKWebView?
    ) {
        switch disposition {
        case .navigatePage(let action):
            navigate(action, in: webView)
        case .switchSpace(let action):
            perform(action)
        case .consume:
            break
        }
    }

    private func navigate(
        _ action: BrowserSidebarMouseButtonAction,
        in webView: WKWebView?
    ) {
        guard let webView else { return }
        switch action {
        case .previousSpace:
            webView.goBack()
        case .nextSpace:
            webView.goForward()
        }
    }

    private func webViewUnderPointer(for event: NSEvent) -> WKWebView? {
        guard let contentView = window?.contentView else { return nil }
        let location = contentView.convert(event.locationInWindow, from: nil)
        var candidate = contentView.hitTest(location)
        while let view = candidate {
            if let webView = view as? WKWebView {
                return webView
            }
            candidate = view.superview
        }
        return nil
    }
}

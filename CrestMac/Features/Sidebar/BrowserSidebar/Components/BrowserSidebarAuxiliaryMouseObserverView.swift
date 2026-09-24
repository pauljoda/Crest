import AppKit

@MainActor
final class BrowserSidebarAuxiliaryMouseObserverView: NSView {
    var perform: @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void
    /// The window's live pages, asked for at event time so a page created or
    /// released since the last SwiftUI update is never consulted.
    var navigationTargets:
        @MainActor @Sendable () -> [any BrowserSidebarMouseNavigationTarget]
    private var eventMonitor: Any?

    init(
        perform: @escaping @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void,
        navigationTargets: @escaping @MainActor @Sendable ()
            -> [any BrowserSidebarMouseNavigationTarget]
    ) {
        self.perform = perform
        self.navigationTargets = navigationTargets
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

        let page = pageUnderPointer(for: event)
        guard
            let disposition = BrowserSidebarMouseButtonPolicy.disposition(
                for: action,
                pointerScope: pointerScope(for: event, page: page),
                canNavigatePage: canNavigate(action, in: page)
            )
        else { return event }

        execute(disposition, in: page)
        return nil
    }

    private func pointerScope(
        for event: NSEvent,
        page: (any BrowserSidebarMouseNavigationTarget)?
    ) -> BrowserSidebarMousePointerScope {
        if page != nil { return .webpage }
        guard !isHidden else { return .unowned }
        let location = convert(event.locationInWindow, from: nil)
        return bounds.contains(location) ? .sidebar : .unowned
    }

    private func canNavigate(
        _ action: BrowserSidebarMouseButtonAction,
        in page: (any BrowserSidebarMouseNavigationTarget)?
    ) -> Bool {
        guard let page else { return false }
        return switch action {
        case .previousSpace:
            page.live.canGoBack
        case .nextSpace:
            page.live.canGoForward
        }
    }

    private func execute(
        _ disposition: BrowserSidebarMouseButtonDisposition,
        in page: (any BrowserSidebarMouseNavigationTarget)?
    ) {
        switch disposition {
        case .navigatePage(let action):
            navigate(action, in: page)
        case .switchSpace(let action):
            perform(action)
        case .consume:
            break
        }
    }

    private func navigate(
        _ action: BrowserSidebarMouseButtonAction,
        in page: (any BrowserSidebarMouseNavigationTarget)?
    ) {
        guard let page else { return }
        switch action {
        case .previousSpace:
            page.goBack()
        case .nextSpace:
            page.goForward()
        }
    }

    /// Matches the hit view against the pages this window owns rather than a
    /// view class, so every engine's page content answers the same way.
    private func pageUnderPointer(
        for event: NSEvent
    ) -> (any BrowserSidebarMouseNavigationTarget)? {
        guard let contentView = window?.contentView else { return nil }
        let targets = navigationTargets()
        guard !targets.isEmpty else { return nil }
        let location = contentView.convert(event.locationInWindow, from: nil)
        var candidate = contentView.hitTest(location)
        while let view = candidate {
            if let match = targets.first(where: { $0.nativeView === view }) {
                return match
            }
            candidate = view.superview
        }
        return nil
    }
}

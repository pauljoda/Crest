import AppKit

@MainActor
final class BrowserQuickWindowGeometryHostView: NSView {
    private var observers: [NSObjectProtocol] = []
    private weak var pagePoolRegistry: BrowserPagePoolRegistry?
    private var targetWindowID: BrowserWindowID?
    private weak var observedWebContentView: NSView?
    private var observedWebContentViewPostedFrameChanges = false
    private var observedWebContentViewPostedBoundsChanges = false
    private var isApplyingFrame = false

    init(
        pagePoolRegistry: BrowserPagePoolRegistry?,
        targetWindowID: BrowserWindowID?
    ) {
        self.pagePoolRegistry = pagePoolRegistry
        self.targetWindowID = targetWindowID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            stopObserving()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeGeometryChanges()
        scheduleGeometryUpdate()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func configure(
        pagePoolRegistry: BrowserPagePoolRegistry?,
        targetWindowID: BrowserWindowID?
    ) {
        guard self.pagePoolRegistry !== pagePoolRegistry
            || self.targetWindowID != targetWindowID
        else { return }
        self.pagePoolRegistry = pagePoolRegistry
        self.targetWindowID = targetWindowID
        observeGeometryChanges()
    }

    static func targetFrame(
        sourceWebContentFrame: CGRect?,
        fallbackVisibleFrame: CGRect
    ) -> CGRect {
        let referenceFrame = sourceWebContentFrame.flatMap { frame in
            guard frame.width > 0, frame.height > 0 else { return nil }
            return frame
        } ?? fallbackVisibleFrame
        return BrowserTransientWindowGeometryPolicy.centeredContentFrame(
            in: referenceFrame
        )
    }

    func updateWindowGeometry() {
        guard !isApplyingFrame,
            let window,
            let screen = window.screen ?? NSScreen.main
        else { return }
        let sourceWebContentFrame = targetWindowID.flatMap { targetWindowID in
            pagePoolRegistry?
                .runtime(for: targetWindowID)?
                .activeWebContentFrame
        }
        let frame = Self.targetFrame(
            sourceWebContentFrame: sourceWebContentFrame,
            fallbackVisibleFrame: screen.visibleFrame
        )
        guard !framesApproximatelyEqual(window.frame, frame) else { return }
        isApplyingFrame = true
        window.setFrame(frame, display: true, animate: false)
        isApplyingFrame = false
    }

    func stopObserving() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        restoreWebContentViewNotificationBehavior()
    }

    private func observeGeometryChanges() {
        stopObserving()
        guard let window else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleGeometryUpdate()
                }
            }
        ]
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleGeometryUpdate()
                }
            }
        )
        guard let sourceWebContentView else { return }
        observedWebContentView = sourceWebContentView
        observedWebContentViewPostedFrameChanges =
            sourceWebContentView.postsFrameChangedNotifications
        observedWebContentViewPostedBoundsChanges =
            sourceWebContentView.postsBoundsChangedNotifications
        sourceWebContentView.postsFrameChangedNotifications = true
        sourceWebContentView.postsBoundsChangedNotifications = true
        observe(
            name: NSView.frameDidChangeNotification,
            object: sourceWebContentView,
            center: center
        )
        observe(
            name: NSView.boundsDidChangeNotification,
            object: sourceWebContentView,
            center: center
        )
        if let sourceWindow = sourceWebContentView.window {
            observe(
                name: NSWindow.didMoveNotification,
                object: sourceWindow,
                center: center
            )
            observe(
                name: NSWindow.didResizeNotification,
                object: sourceWindow,
                center: center
            )
            observe(
                name: NSWindow.didChangeScreenNotification,
                object: sourceWindow,
                center: center
            )
        }
    }

    private var sourceWebContentView: NSView? {
        targetWindowID.flatMap { targetWindowID in
            pagePoolRegistry?
                .runtime(for: targetWindowID)?
                .activeWebContentView
        }
    }

    private func observe(
        name: Notification.Name,
        object: AnyObject,
        center: NotificationCenter
    ) {
        observers.append(
            center.addObserver(
                forName: name,
                object: object,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleGeometryUpdate()
                }
            }
        )
    }

    private func restoreWebContentViewNotificationBehavior() {
        guard let observedWebContentView else { return }
        observedWebContentView.postsFrameChangedNotifications =
            observedWebContentViewPostedFrameChanges
        observedWebContentView.postsBoundsChangedNotifications =
            observedWebContentViewPostedBoundsChanges
        self.observedWebContentView = nil
    }

    private func scheduleGeometryUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updateWindowGeometry()
        }
    }

    private func framesApproximatelyEqual(
        _ first: CGRect,
        _ second: CGRect
    ) -> Bool {
        abs(first.minX - second.minX) < 0.5
            && abs(first.minY - second.minY) < 0.5
            && abs(first.width - second.width) < 0.5
            && abs(first.height - second.height) < 0.5
    }
}

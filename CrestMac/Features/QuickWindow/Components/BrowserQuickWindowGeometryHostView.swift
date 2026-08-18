import AppKit

@MainActor
final class BrowserQuickWindowGeometryHostView: NSView {
    private weak var pagePoolRegistry: BrowserPagePoolRegistry?
    private var targetWindowID: BrowserWindowID?
    private weak var positionedWindow: NSWindow?

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleGeometryUpdate()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func configure(
        pagePoolRegistry: BrowserPagePoolRegistry?,
        targetWindowID: BrowserWindowID?
    ) {
        guard
            self.pagePoolRegistry !== pagePoolRegistry
                || self.targetWindowID != targetWindowID
        else { return }
        self.pagePoolRegistry = pagePoolRegistry
        self.targetWindowID = targetWindowID
    }

    static func targetFrame(
        sourceWebContentFrame: CGRect?,
        fallbackVisibleFrame: CGRect
    ) -> CGRect {
        let referenceFrame =
            sourceWebContentFrame.flatMap { frame in
                guard frame.width > 0, frame.height > 0 else { return nil }
                return frame
            } ?? fallbackVisibleFrame
        return BrowserTransientWindowGeometryPolicy.centeredContentFrame(
            in: referenceFrame
        )
    }

    func updateWindowGeometry() {
        guard let window,
            positionedWindow !== window,
            let screen = window.screen ?? NSScreen.main
        else { return }
        positionedWindow = window
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
        window.setFrame(frame, display: true, animate: false)
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

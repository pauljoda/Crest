import AppKit

/// Places a Quick Window over the page it came from, at the size the person
/// last gave one, and remembers each size they give it afterwards.
@MainActor
final class BrowserQuickWindowGeometryHostView: NSView {
    // MARK: - Static Variables

    /// Where the last size the person gave a Quick Window is kept, beside the
    /// window's other appearance choices and per launch.
    private static let rememberedSizeKey = "crest.quick-window.size"

    // MARK: - Variables

    private weak var pagePoolRegistry: BrowserPagePoolRegistry?
    private var targetWindowID: UUID?
    private weak var positionedWindow: NSWindow?
    /// Whether the window is entering or leaving full screen, whose frames
    /// are AppKit's rather than a size the person chose.
    private var isChangingFullScreen = false

    // MARK: - Initializers

    init(
        pagePoolRegistry: BrowserPagePoolRegistry?,
        targetWindowID: UUID?
    ) {
        self.pagePoolRegistry = pagePoolRegistry
        self.targetWindowID = targetWindowID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions - Attachment

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(self)
        isChangingFullScreen = false
        super.viewWillMove(toWindow: newWindow)
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
        targetWindowID: UUID?
    ) {
        guard
            self.pagePoolRegistry !== pagePoolRegistry
                || self.targetWindowID != targetWindowID
        else { return }
        self.pagePoolRegistry = pagePoolRegistry
        self.targetWindowID = targetWindowID
    }

    // MARK: - Actions - Placement

    /// Centred on the page the Quick Window came from, else that page's
    /// window — a Start Page has no page view to measure — and only then the
    /// screen. It takes `rememberedSize` where the person has given a Quick
    /// Window one, kept within `visibleFrame`, else a size measured against
    /// that page, capped so a wide display does not produce a giant window.
    static func targetFrame(
        sourceWebContentFrame: CGRect?,
        sourceWindowFrame: CGRect? = nil,
        visibleFrame: CGRect,
        rememberedSize: CGSize? = nil
    ) -> CGRect {
        let referenceFrame = usable(sourceWebContentFrame) ?? usable(sourceWindowFrame)
        if let rememberedSize {
            return fitted(rememberedSize, centeredOn: referenceFrame ?? visibleFrame, in: visibleFrame)
        }
        if let referenceFrame {
            return atLeastMinimumSize(BrowserTransientCardArrangement.centeredWindowContentFrame(in: referenceFrame))
        }
        let proposed = BrowserTransientCardArrangement.centeredWindowContentFrame(in: visibleFrame)
        let size = CGSize(
            width: min(proposed.width, BrowserQuickWindowLayout.maximumScreenFallbackWidth),
            height: min(proposed.height, BrowserQuickWindowLayout.maximumScreenFallbackHeight))
        return CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width, height: size.height)
    }

    private static func usable(_ frame: CGRect?) -> CGRect? {
        guard let frame, frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    /// `frame` grown to the window's smallest size, about the same centre: one
    /// side of a split, or a small window, would otherwise open a window its
    /// toolbar does not fit.
    private static func atLeastMinimumSize(_ frame: CGRect) -> CGRect {
        let size = CGSize(
            width: max(frame.width, BrowserQuickWindowLayout.minimumWidth),
            height: max(frame.height, BrowserQuickWindowLayout.minimumHeight))
        return CGRect(
            x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// `size`, no smaller than the window's smallest and no larger than
    /// `visibleFrame`, centred on `reference` and moved only as far as keeps
    /// it inside `visibleFrame`.
    private static func fitted(_ size: CGSize, centeredOn reference: CGRect, in visibleFrame: CGRect) -> CGRect {
        let size = CGSize(
            width: min(max(size.width, BrowserQuickWindowLayout.minimumWidth), visibleFrame.width),
            height: min(max(size.height, BrowserQuickWindowLayout.minimumHeight), visibleFrame.height))
        let x = min(max(reference.midX - size.width / 2, visibleFrame.minX), visibleFrame.maxX - size.width)
        let y = min(max(reference.midY - size.height / 2, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Places the window once, then remembers the sizes the person gives it.
    /// The placement itself is never remembered, so opening a Quick Window
    /// keeps the size another was last given.
    func updateWindowGeometry() {
        guard let window,
            positionedWindow !== window,
            let windowScreen = window.screen ?? NSScreen.main
        else { return }
        positionedWindow = window
        let sourceWebContentFrame = targetWindowID.flatMap { targetWindowID in
            pagePoolRegistry?
                .runtime(for: targetWindowID)?
                .activeWebContentFrame
        }
        let sourceWindowFrame = targetWindowID.flatMap { targetWindowID in
            NSApp.windows.first {
                $0 !== window && $0.identifier?.rawValue == targetWindowID.uuidString
            }?.frame
        }
        // The screen the source window is on, which the Quick Window opens
        // over.
        let screen =
            sourceWindowFrame.flatMap { frame in
                NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
            } ?? windowScreen
        let frame = Self.targetFrame(
            sourceWebContentFrame: sourceWebContentFrame,
            sourceWindowFrame: sourceWindowFrame,
            visibleFrame: screen.visibleFrame,
            rememberedSize: rememberedSize
        )
        if !framesApproximatelyEqual(window.frame, frame) {
            window.setFrame(frame, display: true, animate: false)
        }
        observeSize(of: window)
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

    // MARK: - Actions - Remembered size

    /// The last size the person gave a Quick Window, if it is a usable one.
    private var rememberedSize: CGSize? {
        let defaults = BrowserChromeAppearancePreference.defaults
        guard let data = defaults.data(forKey: Self.rememberedSizeKey),
            let size = try? JSONDecoder().decode(CGSize.self, from: data),
            size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0
        else { return nil }
        return size
    }

    private func observeSize(of window: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification] {
            center.addObserver(self, selector: #selector(rememberSize), name: name, object: window)
        }
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            center.addObserver(self, selector: #selector(beginFullScreenChange), name: name, object: window)
        }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            center.addObserver(self, selector: #selector(endFullScreenChange), name: name, object: window)
        }
    }

    /// Keeps the window's size once a resize settles. A live resize is kept
    /// when it ends, and a zoomed, full-screen or minimized window keeps the
    /// size it had before.
    @objc private func rememberSize() {
        guard let window = positionedWindow, !window.inLiveResize,
            !isChangingFullScreen, !window.styleMask.contains(.fullScreen), !window.isMiniaturized, !window.isZoomed,
            let data = try? JSONEncoder().encode(window.frame.size)
        else { return }
        BrowserChromeAppearancePreference.defaults.set(data, forKey: Self.rememberedSizeKey)
    }

    @objc private func beginFullScreenChange() {
        isChangingFullScreen = true
    }

    @objc private func endFullScreenChange() {
        isChangingFullScreen = false
    }
}

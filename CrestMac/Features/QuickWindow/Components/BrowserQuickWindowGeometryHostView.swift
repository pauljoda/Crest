import AppKit

@MainActor
final class BrowserQuickWindowGeometryHostView: NSView {
    // MARK: - Static Variables

    private static let frameKey = "crest.quick-window.frame"
    private static let frameDefaults: UserDefaults? = {
        let environment = BrowserLaunchEnvironment.current
        guard environment.requiresIsolation else { return .standard }
        guard let isolationID = environment.persistentIsolationID else { return nil }
        return UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID))
    }()
    private static var ephemeralFrame: CGRect?

    // MARK: - Variables

    private let defaults: UserDefaults?
    private weak var pagePoolRegistry: BrowserPagePoolRegistry?
    private var targetWindowID: UUID?
    private weak var positionedWindow: NSWindow?
    private var isChangingFullScreen = false
    private var isWaitingForPlacement = false

    // MARK: - Initializers

    /// Uses launch-scoped preferences by default; nil keeps adjustments only
    /// in memory, and an explicit suite lets validation use disposable state.
    init(
        pagePoolRegistry: BrowserPagePoolRegistry?,
        targetWindowID: UUID?,
        defaults: UserDefaults? = frameDefaults
    ) {
        self.defaults = defaults
        self.pagePoolRegistry = pagePoolRegistry
        self.targetWindowID = targetWindowID
        super.init(frame: .zero)
    }

    /// Geometry hosts require their runtime dependencies and cannot load from a storyboard.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions - Attachment

    /// Drops observations of the previous window before attaching to another.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(self)
        positionedWindow = nil
        isChangingFullScreen = false
        super.viewWillMove(toWindow: newWindow)
    }

    /// Defers placement until the shell has finished applying its initial frame.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleGeometryUpdate()
    }

    /// Leaves pointer input to the page and chrome beneath this geometry bridge.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Actions - Placement

    /// Sized against the page the Quick Window came from, else that page's
    /// window — a Start Page has no page view to measure — and only then the
    /// screen, capped so a wide display does not produce a giant window.
    static func targetFrame(
        sourceWebContentFrame: CGRect?,
        sourceWindowFrame: CGRect? = nil,
        fallbackVisibleFrame: CGRect
    ) -> CGRect {
        let usable: (CGRect?) -> CGRect? = { frame in
            guard let frame, frame.width > 0, frame.height > 0 else { return nil }
            return frame
        }
        if let referenceFrame = usable(sourceWebContentFrame) ?? usable(sourceWindowFrame) {
            return BrowserTransientCardArrangement.centeredWindowContentFrame(in: referenceFrame)
        }
        let proposed = BrowserTransientCardArrangement.centeredWindowContentFrame(in: fallbackVisibleFrame)
        let size = CGSize(
            width: min(proposed.width, BrowserQuickWindowLayout.maximumScreenFallbackWidth),
            height: min(proposed.height, BrowserQuickWindowLayout.maximumScreenFallbackHeight))
        return CGRect(
            x: fallbackVisibleFrame.midX - size.width / 2,
            y: fallbackVisibleFrame.midY - size.height / 2,
            width: size.width, height: size.height)
    }

    /// Places each attached window once, restoring the last adjustment before
    /// observing later changes so automatic placement never becomes the saved preference.
    func updateWindowGeometry() {
        guard let window, positionedWindow !== window, !isWaitingForPlacement else { return }
        let frame: CGRect
        if let remembered = rememberedFrame() {
            frame = restoredFrame(remembered, for: window)
        } else {
            guard let screen = window.screen ?? NSScreen.main else { return }
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
            frame = Self.targetFrame(
                sourceWebContentFrame: sourceWebContentFrame,
                sourceWindowFrame: sourceWindowFrame,
                fallbackVisibleFrame: screen.visibleFrame
            )
        }
        positionedWindow = window
        if !framesApproximatelyEqual(window.frame, frame) {
            window.setFrame(frame, display: true, animate: false)
        }
        // Initial placement must not replace the frame another Quick Window
        // most recently kept. Every open window can save later adjustments.
        observeGeometry(of: window)
    }

    /// Fits a saved frame to the display it overlaps most, falling back to the
    /// current display when its original display is gone. Visible bounds take
    /// precedence over minimum size when a display cannot accommodate both.
    private func restoredFrame(_ frame: CGRect, for window: NSWindow) -> CGRect {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let bestScreen = screens.max { first, second in
            let firstOverlap = first.intersection(frame)
            let secondOverlap = second.intersection(frame)
            return firstOverlap.width * firstOverlap.height < secondOverlap.width * secondOverlap.height
        }
        let visibleFrame =
            bestScreen.flatMap { $0.intersects(frame) ? $0 : nil }
            ?? window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? screens.first
        guard let visibleFrame else { return frame }
        let minimum = window.frameRect(forContentRect: CGRect(origin: .zero, size: window.contentMinSize)).size
        let size = CGSize(
            width: min(max(frame.width, minimum.width), visibleFrame.width),
            height: min(max(frame.height, minimum.height), visibleFrame.height))
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height),
            width: size.width, height: size.height)
    }

    // MARK: - Actions - Persistence

    /// Reads the latest shared adjustment, rejecting malformed persisted geometry.
    private func rememberedFrame() -> CGRect? {
        let frame: CGRect?
        if let defaults {
            frame = defaults.data(forKey: Self.frameKey).flatMap { try? JSONDecoder().decode(CGRect.self, from: $0) }
        } else {
            frame = Self.ephemeralFrame
        }
        guard let frame, Self.isUsable(frame) else { return nil }
        return frame
    }

    /// Tracks adjustments and fullscreen transitions only for the attached window.
    private func observeGeometry(of window: NSWindow) {
        let center = NotificationCenter.default
        for name in [
            NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
        ] {
            center.addObserver(self, selector: #selector(rememberWindowFrame), name: name, object: window)
        }
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            center.addObserver(self, selector: #selector(beginFullScreenChange), name: name, object: window)
        }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            center.addObserver(self, selector: #selector(endFullScreenChange), name: name, object: window)
        }
    }

    /// Saves only usable normal-window frames; temporary system states and
    /// intermediate live-resize frames must not replace the person's preference.
    @objc private func rememberWindowFrame() {
        guard let window = positionedWindow,
            !isChangingFullScreen, !window.styleMask.contains(.fullScreen), !window.isZoomed,
            !window.inLiveResize, !window.isMiniaturized, Self.isUsable(window.frame)
        else { return }
        if let defaults {
            guard let data = try? JSONEncoder().encode(window.frame) else { return }
            defaults.set(data, forKey: Self.frameKey)
        } else {
            Self.ephemeralFrame = window.frame
        }
    }

    /// Suppresses frame capture while AppKit changes fullscreen presentation.
    @objc private func beginFullScreenChange() {
        isChangingFullScreen = true
    }

    /// Allows later adjustments to save again without saving the transition itself.
    @objc private func endFullScreenChange() {
        isChangingFullScreen = false
    }

    /// Requires finite coordinates and positive stored dimensions, since CGRect's
    /// width and height accessors otherwise conceal negative persisted sizes.
    private static func isUsable(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.size.width > 0 && frame.size.height > 0
    }

    /// Holds synchronous bridge updates until the next main-loop turn, after
    /// the hosting controller and shell finish their initial sizing and centering.
    private func scheduleGeometryUpdate() {
        // The hosting controller and shell finish setting the initial size
        // and centering before this attachment's saved placement is applied.
        isWaitingForPlacement = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isWaitingForPlacement = false
            updateWindowGeometry()
        }
    }

    /// Avoids a redundant AppKit frame update for differences below half a point.
    private func framesApproximatelyEqual(
        _ first: CGRect,
        _ second: CGRect
    ) -> Bool {
        abs(first.minX - second.minX) < 0.5
            && abs(first.minY - second.minY) < 0.5
            && abs(first.width - second.width) < 0.5
            && abs(first.height - second.height) < 0.5
    }

    // MARK: - Mutators

    /// Refreshes the opener used for first-use placement without repositioning
    /// a window whose initial geometry has already been applied.
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
}

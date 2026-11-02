import AppKit

/// Places a Quick Window over the page it came from, or when another app asked
/// for it, over the window the person is in there, at the size the person last
/// gave one and clear of another Quick Window, and remembers each size they
/// give it afterwards.
@MainActor
final class BrowserQuickWindowGeometryHostView: NSView {
    // MARK: - Static Variables

    /// Where the last size the person gave a Quick Window is kept, beside the
    /// window's other appearance choices and per launch.
    private static let rememberedSizeKey = "crest.quick-window.size"
    /// What the view hears from the window it placed, and what each tells it.
    private static let observations: [(name: Notification.Name, selector: Selector)] = [
        (NSWindow.didResizeNotification, #selector(BrowserQuickWindowGeometryHostView.rememberSize)),
        (NSWindow.didEndLiveResizeNotification, #selector(BrowserQuickWindowGeometryHostView.rememberSize)),
        (NSWindow.willEnterFullScreenNotification, #selector(BrowserQuickWindowGeometryHostView.beginFullScreenChange)),
        (NSWindow.willExitFullScreenNotification, #selector(BrowserQuickWindowGeometryHostView.beginFullScreenChange)),
        (NSWindow.didEnterFullScreenNotification, #selector(BrowserQuickWindowGeometryHostView.endFullScreenChange)),
        (NSWindow.didExitFullScreenNotification, #selector(BrowserQuickWindowGeometryHostView.endFullScreenChange)),
    ]
    /// The Quick Windows already placed, which a new one opens clear of.
    private static let placedWindows = NSHashTable<NSWindow>.weakObjects()

    // MARK: - Variables

    private weak var pagePoolRegistry: BrowserPagePoolRegistry?
    private var targetWindowID: UUID?
    /// Whether the window opens where the person is, over the window they
    /// are in in another app, instead of over the page it came from.
    private let opensWherePersonIs: Bool
    private weak var positionedWindow: NSWindow?
    /// The window whose resizes the view remembers.
    private weak var observedWindow: NSWindow?
    /// Whether the window is entering or leaving full screen, whose frames
    /// are AppKit's rather than a size the person chose.
    private var isChangingFullScreen = false

    // MARK: - Initializers

    init(
        pagePoolRegistry: BrowserPagePoolRegistry?,
        targetWindowID: UUID?,
        opensWherePersonIs: Bool = false
    ) {
        self.pagePoolRegistry = pagePoolRegistry
        self.targetWindowID = targetWindowID
        self.opensWherePersonIs = opensWherePersonIs
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions - Attachment

    /// Stops remembering the window's sizes only when the view leaves it,
    /// not when it moves within it.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== observedWindow { stopObservingSize() }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Back in the window it already placed, the view goes on remembering its
    /// sizes without placing it again.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, window === positionedWindow { observeSize(of: window) }
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
        // A window another app asked for opens where the person is, over the
        // window they are in there, not over the Crest window it would move
        // into, which may be on another display.
        let sourceTarget = opensWherePersonIs ? nil : targetWindowID
        let sourceWebContentFrame = sourceTarget.flatMap { targetWindowID in
            pagePoolRegistry?
                .runtime(for: targetWindowID)?
                .activeWebContentFrame
        }
        let person = opensWherePersonIs ? Self.wherePersonIs() : nil
        let sourceWindowFrame =
            opensWherePersonIs
            ? person?.window
            : sourceTarget.flatMap { targetWindowID in
                NSApp.windows.first {
                    $0 !== window && $0.identifier?.rawValue == targetWindowID.uuidString
                }?.frame
            }
        // The screen the source window is on, which the Quick Window opens
        // over, or for a window another app asked for, the screen the person
        // is on.
        let screen =
            person?.screen
            ?? sourceWindowFrame.flatMap { frame in
                NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
            } ?? windowScreen
        let placed = Self.targetFrame(
            sourceWebContentFrame: sourceWebContentFrame,
            sourceWindowFrame: sourceWindowFrame,
            visibleFrame: screen.visibleFrame,
            rememberedSize: rememberedSize
        )
        let others = Self.placedWindows.allObjects.filter { $0 !== window && $0.isVisible }.map(\.frame)
        let frame = Self.cascaded(placed, clearOf: others, in: screen.visibleFrame)
        Self.placedWindows.add(window)
        if !framesApproximatelyEqual(window.frame, frame) {
            window.setFrame(frame, display: true, animate: false)
        }
        observeSize(of: window)
    }

    /// Moves `window`, a Quick Window already open that another app asks for
    /// again, to where the person is now, at the size it has and clear of the
    /// other Quick Windows, as a new one would open there.
    static func moveWherePersonIs(_ window: NSWindow) {
        let person = wherePersonIs()
        guard let screen = person.screen ?? window.screen ?? NSScreen.main else { return }
        let moved = fitted(window.frame.size, centeredOn: person.window ?? screen.visibleFrame, in: screen.visibleFrame)
        let others = placedWindows.allObjects.filter { $0 !== window && $0.isVisible }.map(\.frame)
        window.setFrame(cascaded(moved, clearOf: others, in: screen.visibleFrame), display: true, animate: false)
    }

    /// Where the person is: the window they are in in another app, and the
    /// screen it is on, or with no such window, the screen under the pointer.
    private static func wherePersonIs() -> (window: CGRect?, screen: NSScreen?) {
        let window = frontWindowFrameOutsideCrest()
        let screen =
            window.flatMap { frame in
                NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
            } ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        return (window, screen)
    }

    /// The frame, in screen coordinates, of the frontmost ordinary window
    /// another app shows: the window the person is in, which only Crest's own
    /// windows coming forward could hide. The window list gives each window's
    /// bounds and owner without asking for any permission.
    private static func frontWindowFrameOutsideCrest() -> CGRect? {
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
            let primary = NSScreen.screens.first
        else { return nil }
        let crest = ProcessInfo.processInfo.processIdentifier
        let minimum = BrowserQuickWindowLayout.minimumForeignWindowSize
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                (info[kCGWindowOwnerPID as String] as? pid_t) != crest,
                (info[kCGWindowAlpha as String] as? Double).map({ $0 > 0 }) ?? true,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let width = bounds["Width"], let height = bounds["Height"], let x = bounds["X"], let y = bounds["Y"],
                width >= minimum, height >= minimum
            else { continue }
            // The window list measures from the top of the main display;
            // AppKit measures from its bottom.
            return CGRect(x: x, y: primary.frame.maxY - y - height, width: width, height: height)
        }
        return nil
    }

    /// `frame`, kept inside `visibleFrame` and moved a step at a time while
    /// another Quick Window opens at the same place there, as new windows
    /// cascade on the Mac: down and to the right, or up and to the left where
    /// the screen's edge stops it.
    static func cascaded(_ frame: CGRect, clearOf others: [CGRect], in visibleFrame: CGRect) -> CGRect {
        let step = BrowserQuickWindowLayout.cascadeStep
        let inside = { (candidate: CGRect) -> CGRect in
            CGRect(
                x: max(min(candidate.minX, visibleFrame.maxX - candidate.width), visibleFrame.minX),
                y: min(max(candidate.minY, visibleFrame.minY), visibleFrame.maxY - candidate.height),
                width: candidate.width, height: candidate.height)
        }
        let isClear = { (candidate: CGRect) in
            !others.contains { abs($0.minX - candidate.minX) < step / 2 && abs($0.maxY - candidate.maxY) < step / 2 }
        }
        let start = inside(frame)
        guard !isClear(start) else { return start }
        // Down and to the right first; once the screen's edge holds a step
        // back, up and to the left.
        for count in 1...BrowserQuickWindowLayout.cascadeLimit {
            for direction: CGFloat in [1, -1] {
                let offset = step * CGFloat(count) * direction
                let candidate = inside(frame.offsetBy(dx: offset, dy: -offset))
                if isClear(candidate) { return candidate }
            }
        }
        return start
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
        guard observedWindow !== window else { return }
        stopObservingSize()
        observedWindow = window
        for observation in Self.observations {
            NotificationCenter.default.addObserver(
                self, selector: observation.selector, name: observation.name, object: window)
        }
    }

    private func stopObservingSize() {
        if let observedWindow {
            for observation in Self.observations {
                NotificationCenter.default.removeObserver(self, name: observation.name, object: observedWindow)
            }
        }
        observedWindow = nil
        isChangingFullScreen = false
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

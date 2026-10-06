import AppKit

// MARK: - Types

struct BrowserNativeWindowChromeSnapshot {
    let styleMask: NSWindow.StyleMask
    let titlebarAppearsTransparent: Bool
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarSeparatorStyle: NSTitlebarSeparatorStyle
    let toolbar: NSToolbar?
    let toolbarStyle: NSWindow.ToolbarStyle
    let contentFrameClipsToBounds: Bool
    let buttonVisibility: [(NSWindow.ButtonType, Bool)]
}

/// Styles the window that shows Crest's chrome, which acts as the window's
/// title bar: the title bar is transparent and shows no title, and the
/// window's own controls sit on the sidebar.
///
/// In fullscreen the title bar slides down over the page with the menu bar,
/// so there it is the system's standard one, from the moment the window is
/// fullscreen until it starts to leave. Neither writes the fullscreen bit of
/// the style mask, which AppKit owns during its transitions.
///
/// The window's toolbar only holds the title bar's metrics, so it shows only
/// outside fullscreen, whoever shows it. AppKit keeps a fullscreen window's
/// visible toolbar on screen once the title bar has revealed, and an empty one
/// would stay behind as a bar across the top of the window.
@MainActor
final class BrowserNativeWindowControlsHostView: NSView {
    // MARK: - Variables

    private var originalChrome: BrowserNativeWindowChromeSnapshot?
    private var chromeToolbar: BrowserChromeToolbar?
    /// Follows the toolbar's visibility, which SwiftUI's bar appearance sets
    /// to shown whenever the window's content changes its bar preferences.
    private var toolbarVisibilityObservation: NSKeyValueObservation?
    private var windowObservers: [NSObjectProtocol] = []
    private var nativeButtonOrigins: [NSWindow.ButtonType: CGFloat] = [:]
    var sidebarPosition: CGFloat = 0
    var sidebarOnRight: Bool {
        get { sidebarPosition == 1 }
        set { sidebarPosition = newValue ? 1 : 0 }
    }
    var sidebarWidth: CGFloat = BrowserChromeLayout.sidebarIdealWidth
    var isVisible = true {
        didSet {
            guard isVisible != oldValue else { return }
            applyBrowserChrome()
        }
    }
    /// Whether the window shows the system's standard title bar: while it is
    /// fullscreen, and not once it starts to leave.
    private var showsStandardTitleBar = false

    // MARK: - Actions - Window

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            restoreWindowChrome()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        showsStandardTitleBar = window?.styleMask.contains(.fullScreen) ?? false
        captureOriginalChrome()
        observeWindow()
        applyBrowserChrome()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        positionWindowControls()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Actions - Chrome

    func applyBrowserChrome() {
        guard let window else { return }
        // The window stays movable, so its title bar and the system's window
        // commands move it as they move any window. A page under the title bar
        // keeps its presses through `BrowserWindowTitleBarGuard`.
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        applyTitleBar(to: window)
        applySystemToolbarMetrics(to: window)
        let shouldShowWindowControls =
            BrowserNativeWindowControlsPolicy.showsWindowControls(
                sidebarPresentationShowsControls: isVisible,
                in: window.styleMask
            )
        for type in BrowserNativeWindowControlsPolicy.buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            let shouldHide = !shouldShowWindowControls
            guard button.isHidden != shouldHide else { continue }
            button.isHidden = shouldHide
        }
        positionWindowControls()
    }

    /// Shows the title bar as Crest's chrome, transparent and without a title
    /// or separator, or while the window is fullscreen as the system's
    /// standard one.
    private func applyTitleBar(to window: NSWindow) {
        let standard = showsStandardTitleBar
        let titleVisibility: NSWindow.TitleVisibility = standard ? .visible : .hidden
        if window.titleVisibility != titleVisibility {
            window.titleVisibility = titleVisibility
        }
        if window.titlebarAppearsTransparent == standard {
            window.titlebarAppearsTransparent = !standard
        }
        let separatorStyle: NSTitlebarSeparatorStyle = standard ? .automatic : .none
        if window.titlebarSeparatorStyle != separatorStyle {
            window.titlebarSeparatorStyle = separatorStyle
        }
    }

    /// Move the existing AppKit controls inside their titlebar, retaining their
    /// native actions, accessibility, sizes and order. Fullscreen owns placement.
    private func positionWindowControls() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let offset =
            BrowserNativeWindowControlsPolicy.sidebarOffset(
                onRight: true,
                windowWidth: window.contentView?.bounds.width ?? bounds.width,
                sidebarWidth: sidebarWidth,
                in: window.styleMask
            ) * sidebarPosition
        for type in BrowserNativeWindowControlsPolicy.buttonTypes {
            guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
            if nativeButtonOrigins[type] == nil {
                nativeButtonOrigins[type] = parent.convert(button.frame.origin, to: nil).x
            }
            guard let nativeX = nativeButtonOrigins[type] else { continue }
            let target = parent.convert(NSPoint(x: nativeX + offset, y: 0), from: nil).x
            if abs(button.frame.minX - target) > 0.5 {
                button.setFrameOrigin(NSPoint(x: target, y: button.frame.minY))
            }
        }
    }

    func restoreWindowChrome() {
        stopObservingWindow()
        guard let window, let originalChrome else { return }
        sidebarOnRight = false
        positionWindowControls()
        nativeButtonOrigins.removeAll()
        window.styleMask = BrowserNativeWindowControlsPolicy.restoredStyleMask(
            original: originalChrome.styleMask, current: window.styleMask)
        window.titleVisibility = originalChrome.titleVisibility
        window.titlebarAppearsTransparent = originalChrome.titlebarAppearsTransparent
        window.titlebarSeparatorStyle = originalChrome.titlebarSeparatorStyle
        window.toolbar = originalChrome.toolbar
        window.toolbarStyle = originalChrome.toolbarStyle
        window.contentView?.superview?.clipsToBounds =
            originalChrome.contentFrameClipsToBounds
        for (type, wasHidden) in originalChrome.buttonVisibility {
            window.standardWindowButton(type)?.isHidden = wasHidden
        }
        toolbarVisibilityObservation = nil
        chromeToolbar = nil
        self.originalChrome = nil
    }

    private func captureOriginalChrome() {
        guard let window, originalChrome == nil else { return }
        originalChrome = BrowserNativeWindowChromeSnapshot(
            styleMask: window.styleMask,
            titlebarAppearsTransparent: window.titlebarAppearsTransparent,
            titleVisibility: window.titleVisibility,
            titlebarSeparatorStyle: window.titlebarSeparatorStyle,
            toolbar: window.toolbar,
            toolbarStyle: window.toolbarStyle,
            contentFrameClipsToBounds:
                window.contentView?.superview?.clipsToBounds ?? false,
            buttonVisibility: BrowserNativeWindowControlsPolicy.buttonTypes.map { type in
                (type, window.standardWindowButton(type)?.isHidden ?? false)
            }
        )
    }

    private func applySystemToolbarMetrics(to window: NSWindow) {
        window.contentView?.superview?.clipsToBounds = true
        let toolbar: BrowserChromeToolbar
        if let chromeToolbar {
            toolbar = chromeToolbar
        } else {
            toolbar = BrowserChromeToolbar(
                identifier: BrowserNativeWindowControlsPolicy.toolbarIdentifier
            )
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            toolbar.displayMode = .iconOnly
            toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: 0)
            chromeToolbar = toolbar
            toolbarVisibilityObservation = toolbar.observe(\.isVisible) { [weak self] _, _ in
                // Settle after whoever changed it finishes its own update.
                DispatchQueue.main.async { [weak self] in
                    self?.applyBrowserChrome()
                }
            }
        }

        toolbar.chromeWindow = window
        if window.toolbar !== toolbar {
            window.toolbar = toolbar
        }
        if window.toolbarStyle != .unified {
            window.toolbarStyle = .unified
        }
        let shouldShowToolbar = BrowserNativeWindowControlsPolicy.showsToolbar(
            in: window.styleMask
        )
        if toolbar.isVisible != shouldShowToolbar {
            toolbar.isVisible = shouldShowToolbar
        }
    }

    // MARK: - Actions - Observing

    private func observeWindow() {
        stopObservingWindow()
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didUpdateNotification,
            NSWindow.didResizeNotification,
            NSWindow.willEnterFullScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ]
        windowObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.windowChanged(name)
                }
            }
        }
    }

    private func windowChanged(_ name: Notification.Name) {
        switch name {
        case NSWindow.didUpdateNotification:
            positionWindowControls()
            return
        case NSWindow.willEnterFullScreenNotification:
            let position = sidebarPosition
            sidebarPosition = 0
            positionWindowControls()
            sidebarPosition = position
            return
        case NSWindow.didEnterFullScreenNotification:
            showsStandardTitleBar = true
        case NSWindow.willExitFullScreenNotification:
            // The title bar returns to the window as it leaves fullscreen, so
            // it is Crest's again before it does.
            showsStandardTitleBar = false
            if let window { applyTitleBar(to: window) }
            return
        case NSWindow.didExitFullScreenNotification:
            showsStandardTitleBar = false
        default:
            break
        }
        DispatchQueue.main.async { [weak self] in
            self?.applyBrowserChrome()
        }
    }

    private func stopObservingWindow() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
}

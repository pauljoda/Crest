import AppKit

@MainActor
final class BrowserNativeWindowControlsHostView: NSView {
    private var originalChrome: BrowserNativeWindowChromeSnapshot?
    private var chromeToolbar: NSToolbar?
    private var windowObservers: [NSObjectProtocol] = []
    var isVisible = true {
        didSet {
            guard isVisible != oldValue else { return }
            applyBrowserChrome()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            restoreWindowChrome()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        captureOriginalChrome()
        observeWindow()
        applyBrowserChrome()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func applyBrowserChrome() {
        guard let window else { return }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if window.titlebarSeparatorStyle != .none {
            window.titlebarSeparatorStyle = .none
        }
        applySystemToolbarMetrics(to: window)
        for type in BrowserNativeWindowControlsPolicy.buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            let shouldHide = !isVisible
            guard button.isHidden != shouldHide else { continue }
            button.isHidden = shouldHide
        }
    }

    func restoreWindowChrome() {
        stopObservingWindow()
        guard let window, let originalChrome else { return }
        window.styleMask = originalChrome.styleMask
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
        let toolbar: NSToolbar
        if let chromeToolbar {
            toolbar = chromeToolbar
        } else {
            toolbar = NSToolbar(
                identifier: BrowserNativeWindowControlsPolicy.toolbarIdentifier
            )
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            toolbar.displayMode = .iconOnly
            toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: 0)
            chromeToolbar = toolbar
        }

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

    private func observeWindow() {
        stopObservingWindow()
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ]
        windowObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    DispatchQueue.main.async { [weak self] in
                        self?.applyBrowserChrome()
                    }
                }
            }
        }
    }

    private func stopObservingWindow() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
}

import AppKit

/// Routes AppKit departures to the browser window the person was using.
@MainActor
final class BrowserMacPictureInPictureActivity: NSObject {
    // MARK: - Variables

    private let pagesForWindow: (NSWindow) -> BrowserPagePool?
    private let spaceAccess: BrowserSpaceAccessController
    private weak var focusedWindow: NSWindow?

    // MARK: - Initializers

    init(spaceAccess: BrowserSpaceAccessController, pagesForWindow: @escaping (NSWindow) -> BrowserPagePool?) {
        self.spaceAccess = spaceAccess
        self.pagesForWindow = pagesForWindow
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(
            self, selector: #selector(appWillResignActive), name: NSApplication.willResignActiveNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(desktopDidChange), name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared)
    }

    // MARK: - Actions - Departures

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, pagesForWindow(window) != nil else { return }
        // A window on the destination desktop can become key before the
        // workspace sends its desktop change. Consider the old window first.
        if window !== focusedWindow {
            checkDesktopDeparture()
            focusedWindow = window
        }
        returnToSource(in: window)
    }

    @objc private func appWillResignActive() {
        guard let window = NSApp.keyWindow ?? focusedWindow else { return }
        request(from: window, for: .appSwitch) { $0.isOnActiveSpace && !NSApp.isActive }
    }

    @objc private func desktopDidChange() {
        checkDesktopDeparture()
        if NSApp.isActive, let window = NSApp.keyWindow, window.isOnActiveSpace, pagesForWindow(window) != nil {
            focusedWindow = window
            returnToSource(in: window)
        }
    }

    @objc private func appDidBecomeActive() {
        if let window = NSApp.keyWindow ?? focusedWindow { returnToSource(in: window) }
    }

    private func returnToSource(in window: NSWindow) {
        guard NSApp.isActive, window.isKeyWindow, window.isOnActiveSpace,
            let pages = pagesForWindow(window), pages.presentationWindow === window
        else { return }
        pages.returnPictureInPictureToVisibleSources()
    }

    private func checkDesktopDeparture() {
        guard let window = focusedWindow, !window.isOnActiveSpace else { return }
        focusedWindow = nil
        request(from: window, for: .desktopSwitch) { !$0.isOnActiveSpace }
    }

    private func request(
        from window: NSWindow,
        for trigger: BrowserAutomaticPictureInPictureCoordinator.Trigger,
        while away: @escaping @MainActor (NSWindow) -> Bool
    ) {
        guard let pages = pagesForWindow(window), let tabID = pages.activeTabID else { return }
        // Let the app finish deactivating and the Space lock reach the core
        // before a player can put a surface in front of another app.
        DispatchQueue.main.async { [weak self, weak pages, weak window] in
            guard let self, let pages, let window, pages.presentationWindow === window,
                !window.isMiniaturized, pages.activeTabID == tabID, away(window)
            else { return }
            pages.requestAutomaticPictureInPicture(for: trigger, access: spaceAccess)
        }
    }
}

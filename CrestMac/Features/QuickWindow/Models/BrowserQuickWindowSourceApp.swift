import AppKit

/// The app a Quick Window opens over: the one the person was in when a link
/// or a sign-in from another app, or the Quick Window keys pressed there,
/// reached Crest. The Quick Window opens over the window they are in there,
/// with Crest's other windows behind it, and once they close it, that app
/// has the focus again.
@MainActor
struct BrowserQuickWindowSourceApp {
    // MARK: - Types

    /// A window on screen, as the window list reports it.
    private struct ListedWindow {
        let owner: pid_t
        let layer: Int
        let number: Int
        /// The window's frame in AppKit's screen coordinates.
        let frame: CGRect
    }

    // MARK: - Variables

    let application: NSRunningApplication

    /// Whether the app still runs, so a Quick Window can open over it and
    /// give it the focus back.
    var isRunning: Bool { !application.isTerminated }

    // MARK: - Initializers

    /// `application`, unless it is Crest, or an app with no windows of its
    /// own in the Dock, such as one in the menu bar, which leaves the person
    /// in the app they were in.
    init?(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.activationPolicy == .regular
        else { return nil }
        self.application = application
    }

    /// The app other than Crest whose window is in front: the one the person
    /// is in, while no Crest window shows to cover it.
    static func showingFrontWindow() -> Self? {
        windowsOnScreen().lazy.filter(isOrdinary).compactMap { window in
            Self(NSRunningApplication(processIdentifier: window.owner))
        }.first
    }

    // MARK: - Actions - Placement

    /// Where the person is in the app: its window in front, and the screen
    /// they use it on, the one under the pointer while the pointer is in that
    /// window, which can span two, else the one its centre is on. With no
    /// such window, it is the screen under the pointer, as it is when the app
    /// draws the desktop and the pointer is on another display than its
    /// window: the person may be on the desktop there.
    func wherePersonIs() -> (window: CGRect?, screen: NSScreen?) {
        let windows = Self.windowsOnScreen()
        let pointer = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
        guard let front = frontWindow(among: windows)?.frame else { return (nil, pointerScreen) }
        if front.contains(pointer) { return (front, pointerScreen) }
        let windowScreen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: front.midX, y: front.midY)) }
        if drawsDesktop(among: windows), let pointerScreen, pointerScreen != windowScreen {
            return (nil, pointerScreen)
        }
        return (front, windowScreen ?? pointerScreen)
    }

    /// Orders `windows`, Crest's own, listed front to back, behind the app's
    /// window in front, in the order they have. Bringing Crest forward for the
    /// app's link brings every Crest window over that window, and only the
    /// Quick Window opens there.
    func keepBehind(_ windows: [NSWindow]) {
        guard let front = frontWindow(among: Self.windowsOnScreen()) else { return }
        for window in windows.reversed() {
            window.order(.below, relativeTo: front.number)
        }
    }

    // MARK: - Actions - Focus

    /// Brings the app forward again with the window the person was in, unless
    /// it quit, or they hid it, since.
    func takeFocusBack() {
        guard isRunning, !application.isHidden else { return }
        application.activate(from: NSRunningApplication.current, options: [])
    }

    // MARK: - Actions - Window list

    /// The app's window in front that the person works in.
    private func frontWindow(among windows: [ListedWindow]) -> ListedWindow? {
        windows.first { $0.owner == application.processIdentifier && Self.isOrdinary($0) }
    }

    /// Whether the app draws the desktop, as the Finder does, on any display.
    private func drawsDesktop(among windows: [ListedWindow]) -> Bool {
        let desktopLayer = Int(CGWindowLevelForKey(.desktopIconWindow))
        return windows.contains { $0.owner == application.processIdentifier && $0.layer == desktopLayer }
    }

    /// Whether `window` is one a person works in: on the ordinary layer and
    /// larger than a palette or the invisible windows some apps keep on
    /// screen.
    private static func isOrdinary(_ window: ListedWindow) -> Bool {
        let minimum = BrowserQuickWindowLayout.minimumForeignWindowSize
        return window.layer == 0 && window.frame.width >= minimum && window.frame.height >= minimum
    }

    /// The windows on screen that show, front to back. The window list gives
    /// each window's owner and bounds without asking for any permission.
    private static func windowsOnScreen() -> [ListedWindow] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
            let primary = NSScreen.screens.first
        else { return [] }
        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t,
                let layer = info[kCGWindowLayer as String] as? Int,
                let number = info[kCGWindowNumber as String] as? Int,
                (info[kCGWindowAlpha as String] as? Double).map({ $0 > 0 }) ?? true,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            // The window list measures from the top of the main display;
            // AppKit measures from its bottom.
            let frame = CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            return ListedWindow(owner: owner, layer: layer, number: number, frame: frame)
        }
    }
}

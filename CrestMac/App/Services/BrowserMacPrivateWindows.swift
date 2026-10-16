import Foundation

/// The private browsing windows, which share one private workspace: each shows
/// the same private Spaces and tabs, and private browsing ends, with everything
/// it kept, once the last of them closes.
@MainActor
final class BrowserMacPrivateWindows {
    // MARK: - Types

    /// The stores one private window presents.
    struct Window {
        let browser: BrowserStore
        let pages: BrowserPagePool
        let chrome: BrowserChromeState
        let transientBrowsing: BrowserTransientBrowsingCoordinator
        /// Whether the window may close when the person asks: the core asks
        /// the pages that go with it, which every private page is once no
        /// other private window stays open.
        let closeGate: BrowserWindowCloseGate

        var id: UUID { browser.windowID }
    }

    // MARK: - Variables

    /// The private workspace's own window in the core, which no window shows:
    /// every private window opens over its session, and it starts private
    /// browsing over once the last one closes.
    let browser: BrowserStore
    /// The pages every private window shares.
    let pages: BrowserPagePool
    private let spaceAccess: BrowserSpaceAccessController
    private let utilityDefaults: UserDefaults?
    /// The private windows open now, by their identity in the core.
    private var windows: [UUID: Window] = [:]

    /// The page pool of each private window open now.
    var openWindowPages: [BrowserPagePool] { windows.values.map(\.pages) }

    // MARK: - Initializers

    init(
        browser: BrowserStore, pages: BrowserPagePool, spaceAccess: BrowserSpaceAccessController,
        utilityDefaults: UserDefaults?
    ) {
        self.browser = browser
        self.pages = pages
        self.spaceAccess = spaceAccess
        self.utilityDefaults = utilityDefaults
    }

    // MARK: - Actions - Lookup

    /// The private window open under `id`.
    func window(_ id: UUID) -> Window? {
        windows[id]
    }

    /// Whether `id` names the only private window open, whose closing ends
    /// private browsing.
    func isLast(_ id: UUID) -> Bool {
        windows.keys.allSatisfy { $0 == id }
    }

    // MARK: - Actions - Windows

    /// A new private window, which starts as the private window `sourceID`
    /// shows, or as private browsing starts when none is open.
    func open(copying sourceID: UUID?) -> Window {
        let source = sourceID.flatMap { windows[$0]?.id } ?? browser.windowID
        let windowBrowser = browser.makeWindowStore(BrowserWindowOpening(copying: source))
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
        let windowID = windowBrowser.windowID
        let window = Window(
            browser: windowBrowser,
            pages: pages.makeWindowPool(
                browser: windowBrowser, sharesRuntimes: true, transientBrowsing: transientBrowsing,
                spaceAccess: spaceAccess),
            chrome: BrowserChromeState(utilityPresentation: BrowserUtilityPresentationState(defaults: utilityDefaults)),
            transientBrowsing: transientBrowsing,
            closeGate: BrowserWindowCloseGate(core: browser.core) { [weak self] in
                PrepareToCloseWindows(requestID: UUID(), windowIDs: self?.windowsClosing(with: windowID) ?? [windowID])
            })
        windows[windowID] = window
        return window
    }

    /// Lets go of the private window `id` once it closed. The last one ends
    /// private browsing: the pages and data it kept go, and the workspace
    /// starts over. Answers the profiles the engine may let go of, which are
    /// none while another private window stays open.
    @discardableResult
    func close(_ id: UUID) -> [UUID] {
        guard let window = windows.removeValue(forKey: id) else { return [] }
        (window.browser.interactionObserver as? BrowserSidebarInteractionState)?.cancel()
        window.chrome.dismissCommandPalette()
        window.transientBrowsing.dismissPeek()
        window.pages.releaseWindowPresentation()
        window.browser.close()
        guard windows.isEmpty else { return [] }
        let spaces = browser.spaceModels
        pages.closePrivateBrowsingSession(spaces.map(BrowserSpaceRuntimeAssignment.init(space:)))
        browser.resetPrivateBrowsingSession()
        return spaces.map(\.profileID)
    }

    /// The windows closing `id` closes in the core: the last private window
    /// takes the workspace's own window with it, so the core asks every
    /// private page.
    private func windowsClosing(with id: UUID) -> [UUID] {
        isLast(id) ? [id, browser.windowID] : [id]
    }
}

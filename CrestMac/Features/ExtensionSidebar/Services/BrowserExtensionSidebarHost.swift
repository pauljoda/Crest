import AppKit
import Observation

@Observable
@MainActor
final class BrowserExtensionSidebarHost {
    let store: BrowserExtensionSidebarStore
    let windowID: BrowserWindowID
    private(set) var document: BrowserExtensionSidebarDocument?
    private(set) var icon: NSImage?
    private var presentedSpaceID: SpaceID?
    private var lastPanel: BrowserExtensionSidebarPanel?
    private let browser: BrowserStore
    private let pages: BrowserPagePool
    private let spaceAccess: BrowserSpaceAccessController
    private let windowState: BrowserWindowStateStore?

    init(
        store: BrowserExtensionSidebarStore, windowID: BrowserWindowID, browser: BrowserStore,
        pages: BrowserPagePool, spaceAccess: BrowserSpaceAccessController, windowState: BrowserWindowStateStore?
    ) {
        self.store = store
        self.windowID = windowID
        self.browser = browser
        self.pages = pages
        self.spaceAccess = spaceAccess
        self.windowState = windowState
    }

    var panel: BrowserExtensionSidebarPanel? {
        guard let space = browser.selectedSpace, !spaceAccess.isLocked(space), browser.selectedTab != nil,
            let panel = store.panel(in: windowID, spaceID: space.id, activeTab: browser.selectedTab?.id),
            let url = panel.documentURL,
            pages.extensionControllerPool.extensionPageConfiguration(for: url, in: space.id) != nil
        else { return nil }
        return panel
    }

    var width: CGFloat {
        let value = browser.selectedSpace.flatMap { windowState?.extensionSidebar(for: $0.id)?.width }
        return BrowserExtensionSidebarLayoutMetrics.clampedWidth(
            value.map { CGFloat($0) } ?? BrowserExtensionSidebarLayoutMetrics.defaultWidth)
    }

    func reconcile() {
        let space = browser.selectedSpace
        if let previous = presentedSpaceID, previous != space?.id {
            store.reconcilePresentation(in: windowID, spaceID: previous, activeTab: nil, isAvailable: false)
        }
        presentedSpaceID = space?.id
        if let space {
            store.reconcilePresentation(
                in: windowID, spaceID: space.id, activeTab: browser.selectedTab?.id,
                isAvailable: !spaceAccess.isLocked(space) && browser.selectedTab != nil)
        }
        guard let panel else {
            pages.closeExtensionSidebars(inWindow: windowID)
            document = nil
            lastPanel = nil
            icon = nil
            return
        }
        let next = pages.extensionSidebarDocument(for: panel, in: windowID)
        if document !== next { document = next }
        if lastPanel != panel {
            lastPanel = panel
            icon = pages.extensionSidebarIcon(for: panel)
            var preferences = windowState?.extensionSidebar(for: panel.spaceID) ?? .init()
            preferences.lastClientID = panel.clientID
            windowState?.captureExtensionSidebar(preferences, for: panel.spaceID)
        }
    }

    func close() {
        guard let panel else { return }
        try? store.close(for: panel.clientID, in: windowID, tab: nil)
        reconcile()
    }

    var canToggle: Bool { panel != nil || preferredPanel != nil }

    var availablePanels: [BrowserExtensionSidebarPanel] {
        guard let space = browser.selectedSpace, !spaceAccess.isLocked(space), browser.selectedTab != nil else {
            return []
        }
        return store.availablePanels(in: windowID, spaceID: space.id, activeTab: browser.selectedTab?.id)
            .filter { candidate in
                guard let url = candidate.documentURL else { return false }
                return pages.extensionControllerPool.extensionPageConfiguration(for: url, in: space.id) != nil
            }
    }

    private var preferredPanel: BrowserExtensionSidebarPanel? {
        guard let space = browser.selectedSpace, !spaceAccess.isLocked(space) else { return nil }
        let last = windowState?.extensionSidebar(for: space.id)?.lastClientID
        return availablePanels.first(where: { $0.clientID == last }) ?? availablePanels.first
    }

    func toggle() {
        if panel != nil {
            close()
            return
        }
        guard let preferred = preferredPanel else { return }
        select(preferred)
    }

    func select(_ selected: BrowserExtensionSidebarPanel) {
        guard panel?.clientID != selected.clientID else { return }
        if let url = selected.documentURL,
            let context = pages.extensionControllerPool.extensionPageConfiguration(for: url, in: selected.spaceID)?
                .context
        {
            pages.extensionControllerPool.tabWindowCoordinator.performSidebarAction(for: context, invocation: .menu)
            reconcile()
        }
    }

    func userInteracted() {
        guard let panel, let url = panel.documentURL,
            let configuration = pages.extensionControllerPool.extensionPageConfiguration(for: url, in: panel.spaceID)
        else { return }
        pages.extensionControllerPool.tabWindowCoordinator.noteUserGesture(for: configuration.context)
        if let selected = browser.selectedTab?.id,
            let tab = pages.extensionControllerPool.extensionTab(selected, in: panel.spaceID)
        {
            configuration.context.userGesturePerformed(in: tab)
        }
    }

    func commitWidth(_ width: CGFloat) {
        guard let space = browser.selectedSpace else { return }
        var preferences = windowState?.extensionSidebar(for: space.id) ?? .init()
        preferences.width = Double(BrowserExtensionSidebarLayoutMetrics.clampedWidth(width))
        windowState?.captureExtensionSidebar(preferences, for: space.id)
    }

    func release() {
        pages.closeExtensionSidebars(inWindow: windowID)
        document = nil
        store.release(window: windowID)
    }
}

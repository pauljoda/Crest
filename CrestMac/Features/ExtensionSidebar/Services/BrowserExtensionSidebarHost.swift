import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserExtensionSidebarHost: BrowserTabSidePanelResolving {
    /// What a resolved indicator image is filed under.
    ///
    /// The icon an extension names in its options is part of the identity, so
    /// an extension that swaps its artwork resolves a fresh entry rather than
    /// keeping the old one. A package replaced on disk under the same options
    /// keeps its resolved image until the window releases the host.
    private struct IndicatorIconKey: Hashable {
        let clientID: BrowserExtensionServiceClientID
        let spaceID: SpaceID
        let iconPath: String?
    }

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
    /// Sidebar rows ask for their mark on every layout pass, and package
    /// artwork is read off disk, so a resolved image is kept rather than
    /// re-read. Nothing observable is written, so filling the memo during a
    /// view update cannot invalidate the update that asked for it.
    @ObservationIgnored private var indicatorIcons: [IndicatorIconKey: Image?] = [:]

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
        store.closePresentedPanel(in: windowID, spaceID: panel.spaceID)
        reconcile()
    }

    var canToggle: Bool { panel != nil || preferredPanel != nil }

    /// The icon a switcher row shows for `candidate`; the presented panel's
    /// icon is cached on `icon`, the others are read on demand.
    func icon(for candidate: BrowserExtensionSidebarPanel) -> NSImage? {
        candidate.clientID == panel?.clientID ? icon : pages.extensionSidebarIcon(for: candidate)
    }

    /// What the sidebar's row for `tabID` says about the panel bound to it.
    ///
    /// Only one panel presents at a time, so this answers for every tab in the
    /// Space and not only the selected one: a row's mark promises that
    /// selecting that tab brings its panel back, which is exactly what the
    /// store's binding records. A window-level panel is not a binding and
    /// marks no row — see `BrowserExtensionSidebarStore.boundPanel`.
    func sidePanelPresentation(forTab tabID: TabID, in spaceID: SpaceID)
        -> BrowserTabSidePanelPresentation?
    {
        guard let panel = store.boundPanel(for: tabID, in: windowID, spaceID: spaceID) else { return nil }
        return BrowserTabSidePanelPresentation(title: panel.title, icon: indicatorIcon(for: panel))
    }

    private func indicatorIcon(for panel: BrowserExtensionSidebarPanel) -> Image? {
        var iconPath: String?
        if case .packagePath(let path) = panel.icon { iconPath = path }
        let key = IndicatorIconKey(clientID: panel.clientID, spaceID: panel.spaceID, iconPath: iconPath)
        if let resolved = indicatorIcons[key] { return resolved }
        let resolved = pages.extensionSidebarIcon(for: panel).map {
            Image(nsImage: $0).renderingMode(.original)
        }
        indicatorIcons[key] = resolved
        return resolved
    }

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
        indicatorIcons.removeAll()
        store.release(window: windowID)
    }
}

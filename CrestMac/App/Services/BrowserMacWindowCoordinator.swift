import AppKit
import Observation

/// Normal windows present the app's workspace. Temporary windows own disposable
/// workspaces and borrow the source Space's website profile.
@Observable
@MainActor
final class BrowserMacWindowCoordinator {
    private struct PendingTransfer {
        let sourceWindowID: BrowserWindowID
        let item: BrowserTabDragItem
    }

    let browser: BrowserStore
    private let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    private let windowLayouts: BrowserWindowLayouts
    @ObservationIgnored private var windows: [BrowserWindowID: BrowserMacWindowModel] = [:]
    /// Temporary windows that closed or whose transfer was canceled. They are
    /// never restored, so a scene that asks for one again once it went, as
    /// SwiftUI does while it tears a window down, gets nothing instead of a
    /// new workspace.
    @ObservationIgnored private var retiredTemporaryWindows: Set<BrowserWindowID> = []
    @ObservationIgnored private var pendingTransfers: [BrowserWindowID: PendingTransfer] = [:]
    @ObservationIgnored private var transferExpirations: [BrowserWindowID: Task<Void, Never>] = [:]

    init(
        browser: BrowserStore, pages: BrowserPagePool, spaceAccess: BrowserSpaceAccessController,
        windowLayouts: BrowserWindowLayouts
    ) {
        self.browser = browser
        self.pages = pages
        self.spaceAccess = spaceAccess
        self.windowLayouts = windowLayouts
    }

    func existingModel(for id: BrowserWindowID) -> BrowserMacWindowModel? { windows[id] }

    /// The page pool of each open window.
    var openWindowPages: [BrowserPagePool] { windows.values.map(\.pages) }

    @discardableResult
    func activateExistingWindow(for source: BrowserStore) -> Bool {
        guard let space = source.selectedSpace, !spaceAccess.isLocked(space) else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let candidates = windows.values.filter {
            !$0.isTemporary && $0.window != nil && $0.browser.family === source.family
                && $0.browser.space(matching: assignment) != nil
        }
        let destination =
            candidates.first { $0.browser === source }
            ?? candidates.first { $0.browser.selectedSpace?.id == space.id }
            ?? candidates.first
        guard let destination, let window = destination.window else { return false }
        destination.browser.selectSpace(space.id)
        if let tab = source.selectedTab {
            destination.browser.selectTab(tab.id)
        }
        destination.pages.select(session: destination.browser.presented)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return true
    }

    func preparePresentation(_ window: NSWindow, for id: BrowserWindowID) {
        guard let model = windows[id] else { return }
        model.window = window
        model.tearOffPlacement?.prepare(window)
    }

    func didMeasureRow(_ row: BrowserSidebarReorderRow, in id: BrowserWindowID) {
        guard let model = windows[id], let placement = model.tearOffPlacement, placement.isPending,
            model.browser.space(matching: row.space)?.tabs.contains(where: { .tab($0.id) == row.id }) == true
        else { return }
        placement.place(at: row)
    }

    func model(for request: BrowserMacWindowRequest) -> BrowserMacWindowModel? {
        guard !retiredTemporaryWindows.contains(request.id) else { return nil }
        if let existing = windows[request.id] { return existing }
        let source = request.sourceWindowID.flatMap { windows[$0]?.browser } ?? browser
        let windowBrowser: BrowserStore
        let state: BrowserWindowStateStore
        if request.kind == .temporary {
            guard let assignment = request.sourceAssignment,
                let temporary = browser.makeTemporaryWindowStore(in: assignment, id: request.id)
            else { return nil }
            windowBrowser = temporary
            state = BrowserWindowStateStore(
                id: request.id, browser: temporary, layouts: BrowserWindowLayouts(defaults: nil))
        } else {
            // A window without a record of its own starts as the window it was
            // opened from shows.
            windowBrowser = browser.makeWindowStore(
                BrowserWindowOpening(id: request.id, saved: true, copying: source.windowID))
            state = BrowserWindowStateStore(id: request.id, browser: windowBrowser, layouts: windowLayouts)
        }
        let transient = BrowserTransientBrowsingCoordinator()
        let windowPages = pages.makeWindowPool(
            browser: windowBrowser, sharesRuntimes: request.kind == .normal,
            transientBrowsing: transient, spaceAccess: spaceAccess)
        let model = BrowserMacWindowModel(
            request: request, browser: windowBrowser, pages: windowPages,
            transientBrowsing: transient, windowState: state)
        windows[request.id] = model
        return model
    }

    /// The window a scene opened without a request presents: the initial
    /// window, or while a window presents that one, a window of its own that
    /// starts as the initial window shows. Its model exists before the scene
    /// renders it, so no two scenes ever present one window.
    func defaultWindowRequest() -> BrowserMacWindowRequest {
        let request: BrowserMacWindowRequest = windows[.main] == nil ? .initial : .normal(sourceWindowID: .main)
        _ = model(for: request)
        return request
    }

    @discardableResult
    func attach(_ window: NSWindow, to id: BrowserWindowID) -> Bool {
        guard let model = windows[id] else {
            window.close()
            return false
        }
        model.window = window
        model.tearOffPlacement?.attach(window) { [weak model] in
            model?.pages.setWindowFocused(true)
        }
        window.tabbingMode = .disallowed
        model.pages.bindNativeWindow(window)
        if model.isTemporary {
            window.isRestorable = false
            window.setFrameAutosaveName("")
        }
        _ = completePendingTransfer(to: id)
        return windows[id] === model
    }

    func closeWindow(_ id: BrowserWindowID) {
        guard let model = windows.removeValue(forKey: id) else { return }
        model.tearOffPlacement?.cancel()
        cancelPendingTransfer(to: id)
        for destination in pendingTransfers.keys.filter({ pendingTransfers[$0]?.sourceWindowID == id }) {
            cancelPendingTransfer(to: destination)
        }
        if model.isTemporary {
            model.pages.closeWindowWorkspace()
            model.windowState.removePersistedState()
            model.browser.family.temporarySettingsBrowser?.close()
        } else {
            model.pages.releaseWindowPresentation()
        }
        model.browser.close()
        // A temporary window's workspace is its own and goes with it.
        if model.isTemporary {
            retiredTemporaryWindows.insert(id)
            model.browser.family.close()
        }
    }

    /// Closes each temporary window whose workspace the core closed, because
    /// the Space it borrowed was deleted, took another profile or lost its
    /// owner.
    func reconcileTemporaryWorkspaces() {
        let invalid = windows.values.filter {
            $0.isTemporary && !$0.browser.family.isOpen
        }
        for model in invalid {
            model.pages.closeWindowWorkspace()
            model.window?.close()
            closeWindow(model.id)
        }
    }

    /// Preparing a destination is reversible. The shared workspace changes only
    /// after the new scene has a native window and has accepted the transfer.
    func prepareTearOff(
        _ item: BrowserTabDragItem, from sourceID: BrowserWindowID,
        at point: CGPoint? = nil, grabFraction: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) -> BrowserMacWindowRequest? {
        guard let source = windows[sourceID], canTearOff(item, from: source) else { return nil }
        let request = BrowserMacWindowRequest.temporary(
            sourceWindowID: sourceID, assignment: item.spaceAssignment)
        guard let destination = model(for: request) else { return nil }
        if let point {
            destination.tearOffPlacement = BrowserMacTabTearOffPlacement(
                assignment: item.runtimeAssignment, dropPoint: point, grabFraction: grabFraction)
        }
        pendingTransfers[request.id] = PendingTransfer(sourceWindowID: sourceID, item: item)
        transferExpirations[request.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.cancelPendingTransfer(to: request.id)
        }
        return request
    }

    @discardableResult
    func completePendingTransfer(to destinationID: BrowserWindowID) -> Bool {
        guard let pending = pendingTransfers[destinationID],
            let source = windows[pending.sourceWindowID], let destination = windows[destinationID],
            transfer(pending.item, from: source, to: destination)
        else {
            if pendingTransfers[destinationID] != nil { cancelPendingTransfer(to: destinationID) }
            return false
        }
        pendingTransfers.removeValue(forKey: destinationID)
        transferExpirations.removeValue(forKey: destinationID)?.cancel()
        return true
    }

    func cancelPendingTransfer(to id: BrowserWindowID) {
        transferExpirations.removeValue(forKey: id)?.cancel()
        guard pendingTransfers.removeValue(forKey: id) != nil else { return }
        retiredTemporaryWindows.insert(id)
        guard let destination = windows.removeValue(forKey: id) else { return }
        destination.tearOffPlacement?.cancel()
        destination.pages.closeWindowWorkspace()
        destination.browser.family.temporarySettingsBrowser?.close()
        destination.browser.close()
        destination.browser.family.close()
        destination.window?.close()
    }

    @discardableResult
    func move(_ item: BrowserTabDragItem, from sourceID: BrowserWindowID, to destinationID: BrowserWindowID) -> Bool {
        guard sourceID != destinationID, let source = windows[sourceID], let destination = windows[destinationID]
        else { return false }
        return transfer(item, from: source, to: destination)
    }

    func windowID(at screenPoint: CGPoint, excluding sourceID: BrowserWindowID) -> BrowserWindowID? {
        guard
            let window = NSApp.orderedWindows.first(where: {
                $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(screenPoint)
            })
        else {
            return nil
        }
        return windows.values.first(where: { $0.window === window && $0.id != sourceID })?.id
    }

    func isInsideAnyWindow(screenPoint: CGPoint) -> Bool {
        NSApp.orderedWindows.contains { $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(screenPoint) }
    }

    func isInsideWindow(_ id: BrowserWindowID, screenPoint: CGPoint) -> Bool {
        windows[id]?.window?.frame.contains(screenPoint) == true
    }

    /// The core decides whether the dragged tab may leave its window: the
    /// window still shows the Space with its profile and it is unlocked, holds
    /// the tab, and the drag carries that tab alone. A Space this window is
    /// deleting never lets a tab go.
    private func canTearOff(_ item: BrowserTabDragItem, from model: BrowserMacWindowModel) -> Bool {
        guard model.browser.space(matching: item.spaceAssignment) != nil else { return false }
        let question = CanTearOff(
            windowID: model.browser.windowID.rawValue, spaceID: item.spaceID.rawValue, profileID: item.profileID,
            tabID: item.tabID.rawValue, draggedTabs: item.selection?.ids.map(\.rawValue))
        return (try? model.browser.core.query(question))?.allowed == true
    }

    private func transfer(
        _ item: BrowserTabDragItem, from source: BrowserMacWindowModel, to destination: BrowserMacWindowModel
    ) -> Bool {
        guard canTearOff(item, from: source),
            let targetSpace = destination.browser.space(matching: item.spaceAssignment),
            !spaceAccess.isLocked(targetSpace),
            source.browser.canTransferTab(
                item.tabID, matching: item.spaceAssignment,
                to: destination.browser, in: item.spaceAssignment)
        else { return false }
        guard
            let tab = source.browser.space(matching: item.spaceAssignment)?.tabs.first(where: { $0.id == item.tabID }),
            destination.pages.canTransferTabRuntime(
                from: source.pages,
                matching: item.runtimeAssignment, as: tab, in: targetSpace)
        else { return false }
        guard
            source.browser.transferTab(
                item.tabID, matching: item.spaceAssignment, to: destination.browser, in: item.spaceAssignment)
        else { return false }
        // Both moves have been validated above. There is no actor suspension
        // between committing the workspace graphs and relocating the runtime.
        let movedTab = destination.browser.space(matching: item.spaceAssignment)?.tabs.first { $0.id == tab.id } ?? tab
        let transferred = destination.pages.transferTabRuntime(
            from: source.pages, matching: item.runtimeAssignment, as: movedTab, in: targetSpace)
        assert(transferred)
        source.pages.reconcile(session: source.browser.session)
        source.pages.select(session: source.browser.presented)
        destination.pages.reconcile(session: destination.browser.session)
        destination.pages.select(session: destination.browser.presented)
        if destination.tearOffPlacement?.isPending != true {
            destination.pages.setWindowFocused(true)
            destination.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

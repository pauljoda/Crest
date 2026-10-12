import AppKit

/// Window creation and management methods exposed to automation tools.
extension BrowserMacAutomation {
    // MARK: - Actions - Windows

    /// Opens a new normal browser window over `opening.space`, optionally loading `opening.url`.
    func openWindow(
        _ opening: BrowserAutomationWindowOpening
    ) throws(BrowserAutomationError) -> BrowserAutomationWindowAnswer {
        let space = try resolveSpace(opening.space)
        let request = BrowserMacWindowRequest.normal(sourceWindowID: nil)
        windows.open(request, activation: .key)
        guard let window = application.windowCoordinator.existingModel(for: request.id) else {
            throw .refused("Crest could not open a window.")
        }
        window.browser.selectSpace(space.id)
        var openedTabID: UUID?
        if let addressString = opening.url {
            let url = try address(addressString)
            openedTabID = window.browser.openNewTab(url: url, in: space.id, selecting: true)
        }
        bringForward(window)
        return BrowserAutomationWindowAnswer(windowID: window.id, spaceID: space.id, tabID: openedTabID)
    }

    /// Opens a Blank Window (temporary workspace borrowing the Space session).
    func openBlankWindow(
        _ opening: BrowserAutomationBlankWindowOpening
    ) throws(BrowserAutomationError) -> BrowserAutomationWindowAnswer {
        let space = try resolveSpace(opening.space)
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        let request = BrowserMacWindowRequest.temporary(sourceWindowID: nil, assignment: assignment)
        windows.open(request, activation: .key)
        guard let window = application.windowCoordinator.existingModel(for: request.id) else {
            throw .refused("Crest could not open a Blank Window.")
        }
        bringForward(window)
        return BrowserAutomationWindowAnswer(windowID: window.id, spaceID: space.id, tabID: nil)
    }

    /// Opens a private browsing window, optionally opening a URL.
    func openPrivateWindow(
        _ opening: BrowserAutomationPrivateWindowOpening
    ) throws(BrowserAutomationError) -> BrowserAutomationWindowAnswer {
        windows.openPrivateWindow()
        var openedTabID: UUID?
        if let addressString = opening.url {
            let url = try address(addressString)
            openedTabID = application.privateBrowser.openNewTab(
                url: url, in: application.privatePages.windowID, selecting: true)
        }
        return BrowserAutomationWindowAnswer(
            windowID: application.privatePages.windowID, spaceID: nil, tabID: openedTabID)
    }

    /// Opens a native Crest Quick Window for `opening.url`, anchored to `opening.space`.
    func openQuickWindow(
        _ opening: BrowserAutomationQuickWindowOpening
    ) throws(BrowserAutomationError) -> BrowserAutomationQuickWindowAnswer {
        let url = try address(opening.url)
        let space = try resolveSpace(opening.space)
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        let request = BrowserQuickWindowRequest(url: url, spaceAssignment: assignment)
        windows.openQuickWindow(request)
        return BrowserAutomationQuickWindowAnswer(windowID: request.id, spaceID: space.id, url: opening.url)
    }

    // MARK: - Actions - Helpers

    /// Resolves the requested Space ID or defaults to the first available unlocked Space.
    func resolveSpace(_ id: UUID?) throws(BrowserAutomationError) -> SpaceModel {
        if let id {
            return try space(id)
        }
        let reach = try reach()
        guard let first = reach.spaces.first(where: { !$0.isLocked }),
            let space = reach.workspace.spaces.model(first.spaceID)
        else {
            throw .refused("No accessible Space available.")
        }
        return space
    }
}

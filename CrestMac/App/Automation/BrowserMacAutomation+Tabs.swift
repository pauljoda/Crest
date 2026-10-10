import AppKit

/// What a tool may do with the Spaces and tabs it reaches. Each method reads
/// the core's `AutomationReach` first, so a Space the person stopped allowing,
/// or locked, is out of reach at once. Tabs open, close and come forward
/// through the window stores Crest's own commands use, so the core's rules
/// and a page's leave-page check apply as they do for the person. A tool
/// never opens a window: it works in the windows the person has open.
extension BrowserMacAutomation {
    // MARK: - Actions - Spaces

    /// The Spaces a tool reaches, in the session's order, with whether each
    /// is locked.
    func listSpaces() throws(BrowserAutomationError) -> BrowserAutomationSpaceList {
        BrowserAutomationSpaceList(
            spaces: try reach().spaces.map { .init(id: $0.spaceID, name: $0.name, locked: $0.isLocked) })
    }

    // MARK: - Actions - Tabs

    /// The tabs of every unlocked Space a tool reaches, or of the one the
    /// query names, in sidebar order.
    func listTabs(_ query: BrowserAutomationTabQuery) throws(BrowserAutomationError) -> BrowserAutomationTabList {
        let spaces: [SpaceModel]
        if let id = query.space {
            spaces = [try space(id)]
        } else {
            let reach = try reach()
            spaces = reach.spaces.filter { !$0.isLocked }.compactMap { reach.workspace.spaces.model($0.spaceID) }
        }
        return BrowserAutomationTabList(
            tabs: spaces.flatMap { space in space.tabs.models.map { tab(tab: $0, in: space) } })
    }

    /// Opens an address in a new tab of a Space, after the tab the Space
    /// shows. It comes forward in the front window over the Space when asked
    /// to and one is open, and otherwise opens behind the person's work.
    func openTab(_ opening: BrowserAutomationTabOpening) throws(BrowserAutomationError) -> BrowserAutomationTabAnswer {
        let space = try space(opening.space)
        let url = try address(opening.url)
        let window = frontWindow(over: space)
        let shows = opening.show == true && window != nil
        let browser = window?.browser ?? application.browser
        guard let tabID = browser.openNewTab(url: url, in: space.id, selecting: shows),
            let tab = space.tabs.model(tabID)
        else { throw .refused("Crest could not open a tab in this Space.") }
        if shows, let window { bringForward(window) }
        return BrowserAutomationTabAnswer(tab: self.tab(tab: tab, in: space))
    }

    /// Closes an open tab, once its page agrees to go, as closing it in the
    /// sidebar does. A pinned or saved tab is the person's, and stays. The
    /// core asks a live page whether it may go, which can answer after this
    /// returns, so the answer waits a little for the tab to leave; a page
    /// that asks the person is still open, and the answer says so.
    func closeTab(
        _ reference: BrowserAutomationTabReference
    ) async throws(BrowserAutomationError) -> BrowserAutomationClosed {
        let (space, tab) = try tab(reference.tab)
        guard tab.placement == .current else {
            throw .refused("Tools may close only open tabs, never pinned or saved ones.")
        }
        let browser = frontWindow(over: space)?.browser ?? application.browser
        if browser.closeTab(tab.id, in: space.id) { return BrowserAutomationClosed(closed: true) }
        let deadline = ContinuousClock.now + Self.closeWait
        while space.tabs.contains(tab.id), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return BrowserAutomationClosed(closed: !space.tabs.contains(tab.id))
    }

    /// Brings a tab forward in the front window over its Space, and Crest
    /// with it.
    func showTab(_ reference: BrowserAutomationTabReference) throws(BrowserAutomationError)
        -> BrowserAutomationTabAnswer
    {
        let (space, tab) = try tab(reference.tab)
        guard let window = frontWindow(over: space) else { throw .noWindow }
        window.browser.selectSpace(space.id)
        guard window.browser.activateSessionTab(tab.id, in: space.id) else {
            throw .refused("Crest could not show the tab.")
        }
        bringForward(window)
        return BrowserAutomationTabAnswer(tab: self.tab(tab: tab, in: space))
    }

    // MARK: - Actions - Reach

    /// The person's own workspace and the Spaces a tool reaches in it, as the
    /// core answers.
    private func reach() throws(BrowserAutomationError) -> (workspace: WorkspaceModel, spaces: [AutomationSpace]) {
        guard let reach = try? core.query(AutomationReach()), let id = reach.workspaceID,
            let workspace = core.state.workspaces[id]
        else { throw .automationOff }
        return (workspace, reach.spaces)
    }

    /// The Space `id` names, while a tool reaches it and it is unlocked.
    private func space(_ id: UUID) throws(BrowserAutomationError) -> SpaceModel {
        let reach = try reach()
        guard let reached = reach.spaces.first(where: { $0.spaceID == id }),
            let space = reach.workspace.spaces.model(id)
        else { throw .spaceUnavailable(id) }
        guard !reached.isLocked else { throw .spaceLocked(reached.name) }
        return space
    }

    /// The tab `id` names and its Space, while a tool reaches the Space and
    /// it is unlocked.
    private func tab(_ id: UUID) throws(BrowserAutomationError) -> (SpaceModel, TabStateModel) {
        let reach = try reach()
        for reached in reach.spaces {
            guard let space = reach.workspace.spaces.model(reached.spaceID), let tab = space.tabs.model(id) else {
                continue
            }
            guard !reached.isLocked else { throw .spaceLocked(reached.name) }
            return (space, tab)
        }
        throw .tabUnavailable(id)
    }

    /// `text` as an address a tool may open: http or https, with a host.
    /// Crest's own pages and other schemes stay out of a tool's reach.
    private func address(_ text: String) throws(BrowserAutomationError) -> URL {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
            url.host() != nil
        else { throw .unsupportedAddress }
        return url
    }

    // MARK: - Actions - Windows

    /// The front window over `space`'s workspace, or nil with none open.
    private func frontWindow(over space: SpaceModel) -> BrowserMacWindowModel? {
        application.stackedWindowIDs.lazy.compactMap { self.application.windowCoordinator.existingModel(for: $0) }
            .first { !$0.isTemporary && $0.browser.spaceModel(space.id) != nil }
    }

    /// Shows what `window` selected and brings it forward, and Crest with it.
    private func bringForward(_ window: BrowserMacWindowModel) {
        window.pages.select()
        windows.open(window.request, activation: .key)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions - Descriptions

    /// A tab as a tool reads it. It is shown when a window on screen shows
    /// it, which the core's record of a window alone does not say.
    private func tab(tab: TabStateModel, in space: SpaceModel) -> BrowserAutomationTab {
        BrowserAutomationTab(
            id: tab.id, space: space.id, title: tab.displayTitle, url: tab.url, placement: tab.placement.name,
            shown: application.stackedWindowIDs.contains {
                core.state.windows[$0]?.shownTabIDs.contains(tab.id) == true
            })
    }
}

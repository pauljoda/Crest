/// Shared drag state and the collaborators authorized to commit its result.
@MainActor
struct BrowserSidebarReorderContext {
    // MARK: - Variables

    let state: BrowserSidebarReorderState
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    // MARK: - Initializers

    init(browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, state: BrowserSidebarReorderState) {
        self.state = state
        self.browser = browser
        self.spaceAccess = spaceAccess
    }

    // MARK: - Actions - Lifting

    /// What lifting `item` carries, as the core reads a sidebar selection, and
    /// where the core would let it land, asked once as the lift begins: the
    /// window's selection when the item carries one, and otherwise the row
    /// alone — a tab, every member of a split, or a folder with all it holds.
    func plan(for item: BrowserSidebarReorderItem) -> BrowserSidebarLiftPlan? {
        let assignment = item.spaceAssignment
        let selection: TabSelection
        if let captured = item.selection {
            selection = captured.selection
        } else {
            let (tabIDs, folderIDs): ([TabID], [FolderID]) =
                switch item {
                case .tab(let tab): ([tab.tabID], [])
                case .splitGroup(let group): (group.memberTabIDs, [])
                case .folder(let folder): ([], [folder.folderID])
                }
            guard
                let selected = try? browser.core.query(
                    SelectionPreview(
                        workspaceID: browser.family.workspaceID, spaceID: assignment.spaceID, tabIDs: tabIDs,
                        folderIDs: folderIDs))
            else { return nil }
            // A split row lifts the run it stood for; one the Space no longer
            // holds as that split plans nothing.
            if case .splitGroup(let group) = item {
                guard selected.members.map(\.id) == group.memberTabIDs,
                    selected.members.allSatisfy({ $0.splitGroupID == group.groupID })
                else { return nil }
            }
            // A folder lifted with the tabs it held then drops only while it
            // holds them still; the core refuses a selection whose tabs changed.
            if case .folder(let folder) = item, let snapshot = folder.memberTabIDs {
                selection = TabSelection(
                    tabIDs: selected.selection.tabIDs, folderIDs: selected.selection.folderIDs, memberTabIDs: snapshot)
            } else {
                selection = selected.selection
            }
        }
        let targets = try? browser.core.query(
            DropTargets(
                workspaceID: browser.family.workspaceID, windowID: browser.windowID, spaceID: assignment.spaceID,
                selection: selection))
        return BrowserSidebarLiftPlan(selection: selection, targets: targets)
    }

    // MARK: - Actions - Dropping

    /// Commits a released lift as the core's drop intent for where it landed.
    func commit(_ drop: BrowserSidebarReorderDrop) {
        guard let plan = drop.plan ?? plan(for: drop.item) else { return }
        BrowserSidebarDropCommit(browser: browser, spaceAccess: spaceAccess)
            .commit(drop.target, for: drop.item, plan: plan)
    }
}

#if DEBUG
    import Foundation

    /// TRANSITIONAL until S6.6c2 moves the sidebar onto the core's outline and
    /// deletes the Swift rules. After each batch, every Space a change touched
    /// lists in the read model's sidebar lists what the Swift rules list for
    /// that workspace's copy: each list row by row, as
    /// `BrowserSidebarFolderListItem.Projection` and
    /// `BrowserSidebarTabListItemPolicy` build it, and what a person sees, as
    /// `BrowserSidebarSelection.logicalItems` walks it. A mismatch stops a
    /// debug build, naming the workspace, the Space, the list and its first
    /// differing row on each side.
    extension CoreState {
        // MARK: - Types

        /// The workspaces a batch brought whole, and the Spaces of the others
        /// whose sidebar a change in it can alter.
        private struct SidebarTouches {
            var wholeWorkspaces: Set<UUID> = []
            var spaces: [UUID: Set<UUID>] = [:]

            init(_ changes: [Change]) {
                for change in changes {
                    switch change {
                    case .workspaceOpened(let opened): wholeWorkspaces.insert(opened.workspaceID)
                    case .tabsImported(let imported): wholeWorkspaces.insert(imported.workspaceID)
                    case .spacesChanged(let changed):
                        for space in changed.added { spaces[changed.workspaceID, default: []].insert(space.id) }
                    case .spaceSettingsChanged(let changed):
                        spaces[changed.workspaceID, default: []].insert(changed.spaceID)
                    case .tabsChanged(let changed): spaces[changed.workspaceID, default: []].insert(changed.spaceID)
                    case .foldersChanged(let changed): spaces[changed.workspaceID, default: []].insert(changed.spaceID)
                    case .sidebarChanged(let changed): spaces[changed.workspaceID, default: []].insert(changed.spaceID)
                    default: break
                    }
                }
            }
        }

        // MARK: - Actions - Checking

        /// Checks every Space `changes` touched in a workspace with a
        /// registered copy.
        func checkSidebarOutlines(after changes: [Change]) {
            let touched = SidebarTouches(changes)
            for workspaceID in touched.wholeWorkspaces.union(touched.spaces.keys) {
                guard let copy = sessionCopies[workspaceID]?.authority?.projection,
                    let workspace = workspaces[workspaceID]
                else { continue }
                let spaceIDs =
                    touched.wholeWorkspaces.contains(workspaceID)
                    ? Set(workspace.spaces.models.map(\.id)) : touched.spaces[workspaceID, default: []]
                for spaceID in spaceIDs {
                    guard let space = workspace.spaces.model(spaceID), let copySpace = copy.space(id: spaceID) else {
                        continue
                    }
                    let problems = Self.sidebarProblems(space, copySpace)
                    if !problems.isEmpty {
                        assertionFailure(
                            "Sidebar outline parity, workspace \(workspaceID), Space \(spaceID): "
                                + problems.joined(separator: "; "))
                    }
                }
            }
        }

        private static func sidebarProblems(_ space: SpaceModel, _ copy: BrowserSpace) -> [String] {
            var problems: [String] = []
            for expected in swiftLists(of: copy) {
                let list =
                    expected.folderID.map { space.sidebar.inside($0) } ?? space.sidebar.section(expected.section)
                if let difference = rowDifference(list.rows, expected.rows) {
                    let name = expected.folderID.map { "folder \($0)" } ?? "\(expected.section.name) section"
                    problems.append("\(name): \(difference)")
                }
            }
            let shown = shownItems(of: space)
            let logical = BrowserSidebarSelection.logicalItems(in: copy) { _ in nil }
            if shown != logical {
                let index =
                    zip(shown, logical).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                    ?? min(shown.count, logical.count)
                problems.append(
                    "shown items differ at \(index) of \(shown.count) and \(logical.count): read model "
                        + "\(shown.dropFirst(index).prefix(3)), logicalItems \(logical.dropFirst(index).prefix(3))")
            }
            return problems
        }

        // MARK: - Actions - Swift rules

        /// Every list the Swift rules build for the copy's Space, in the rows
        /// the core's outline spells them with.
        private static func swiftLists(of copy: BrowserSpace) -> [SidebarList] {
            let sections = copy.tabSections
            let tree = copy.folderTree
            let pinned = sections.pinnedTabs.filter { !$0.isStartPage }.map {
                SidebarRow(id: $0.id, kind: .tab, parentFolderID: nil, depth: 0, members: [$0.id])
            }
            var lists = [SidebarList(section: .pinned, folderID: nil, rows: pinned)]
            for location in [BrowserFolderLocation.saved, .current] {
                let projection = BrowserSidebarFolderListItem.Projection(
                    tabs: location == .saved ? copy.tabs : sections.sidebarCurrentTabs, tree: tree, location: location)
                lists.append(
                    SidebarList(
                        section: location.tabPlacement, folderID: nil,
                        rows: rows(of: projection.items(), in: nil, depth: 0)))
                for node in tree.flattenedNodes(collapsedFolderIDs: []) where node.folder.location == location {
                    lists.append(
                        SidebarList(
                            section: location.tabPlacement, folderID: node.id,
                            rows: rows(of: projection.items(in: node.id), in: node.id, depth: node.depth + 1)))
                }
            }
            return lists
        }

        private static func rows(of items: [BrowserSidebarFolderListItem], in folderID: UUID?, depth: Int)
            -> [SidebarRow]
        {
            items.compactMap { item in
                switch item {
                case .folder(let node):
                    return SidebarRow(
                        id: node.id, kind: .folder, parentFolderID: folderID, depth: node.depth, members: [])
                case .tabs(.tab(let tab)):
                    guard !tab.isStartPage else { return nil }
                    return SidebarRow(id: tab.id, kind: .tab, parentFolderID: folderID, depth: depth, members: [tab.id])
                case .tabs(.splitGroup(let groupID, let members)):
                    let shown = members.filter { !$0.isStartPage }.map(\.id)
                    guard !shown.isEmpty else { return nil }
                    return SidebarRow(
                        id: groupID, kind: .split, parentFolderID: folderID, depth: depth, members: shown)
                }
            }
        }

        // MARK: - Actions - Read model

        /// What a person sees of the read model's lists: every section but a
        /// collapsed saved section, skipping the inside of collapsed folders.
        private static func shownItems(of space: SpaceModel) -> [BrowserSelectionItemID] {
            var items: [BrowserSelectionItemID] = []
            func walk(_ rows: [SidebarRow]) {
                for row in rows {
                    guard row.kind.opensList else {
                        items += row.members.map { .tab($0) }
                        continue
                    }
                    items.append(.folder(row.id))
                    if space.folders.model(row.id)?.isCollapsed == false { walk(space.sidebar.inside(row.id).rows) }
                }
            }
            for placement in TabPlacement.all where placement != .saved || space.settings.isSavedTabsExpanded {
                walk(space.sidebar.section(placement).rows)
            }
            return items
        }

        /// Where two lists of rows first differ, or nil when they are equal.
        private static func rowDifference(_ rows: [SidebarRow], _ expected: [SidebarRow]) -> String? {
            guard rows != expected else { return nil }
            let index =
                zip(rows, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                ?? min(rows.count, expected.count)
            func describe(_ list: [SidebarRow]) -> String {
                guard list.indices.contains(index) else { return "nothing" }
                let row = list[index]
                return "\(row.kind.name) \(row.id) in \(row.parentFolderID.map(\.uuidString) ?? "the section") "
                    + "at depth \(row.depth) showing \(row.members)"
            }
            return "\(rows.count) rows, Swift rules \(expected.count); at \(index) read model \(describe(rows)), "
                + "Swift rules \(describe(expected))"
        }
    }
#endif

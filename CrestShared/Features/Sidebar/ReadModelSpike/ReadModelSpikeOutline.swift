#if DEBUG || CREST_PERFORMANCE_HARNESS
    import Foundation
    import Observation

    /// S6.4 spike, DEBUG and performance builds only: the order one Space's
    /// sidebar shows, the way the core will publish it (S6.5a). A batch that
    /// changes the Space's structure rebuilds it from the Space's models, and
    /// it announces only an outline that differs, so a list that reads only
    /// the outline never redraws for a new title or address.
    @MainActor
    @Observable
    final class ReadModelSpikeOutline {
        // MARK: - Types

        /// One row the sidebar shows: a tab, a folder, or a split's members.
        struct Row: Equatable, Identifiable {
            enum Kind {
                case tab
                case folder
                case split
            }

            let id: UUID
            let kind: Kind
            let depth: Int
            /// The tabs the row shows: the tab itself, or the split's members.
            let members: [UUID]
        }

        /// The rows of one section, in order.
        struct Section: Equatable, Identifiable {
            let placement: TabPlacement
            let rows: [Row]

            var id: Int { placement.tag }
        }

        // MARK: - Variables

        let space: SpaceModel
        let workspaceID: UUID
        /// The sections, pinned, saved and current, in order.
        var sections: [Section] { observed(\.sectionsStorage, as: \.sections) }
        @ObservationIgnored private var sectionsStorage: [Section]
        /// How many batches rebuilt the outline, and how long the rebuilds took.
        @ObservationIgnored private(set) var rebuildCount = 0
        @ObservationIgnored private(set) var rebuildDuration = Duration.zero

        // MARK: - Initializers

        init(space: SpaceModel, workspaceID: UUID) {
            self.space = space
            self.workspaceID = workspaceID
            sectionsStorage = Self.sections(of: space)
        }

        // MARK: - Actions - Batches

        /// Rebuilds the outline when a change in `changes` can change the
        /// Space's structure.
        func receive(_ changes: [Change]) {
            guard changes.contains(where: changesStructure) else { return }
            let start = ContinuousClock.now
            publish(Self.sections(of: space), into: \.sectionsStorage, as: \.sections)
            rebuildCount += 1
            rebuildDuration += start.duration(to: .now)
        }

        private func changesStructure(_ change: Change) -> Bool {
            switch change {
            case .tabsChanged(let changed): changed.workspaceID == workspaceID && changed.spaceID == space.id
            case .foldersChanged(let changed): changed.workspaceID == workspaceID && changed.spaceID == space.id
            case .workspaceOpened(let opened): opened.workspaceID == workspaceID
            default: false
            }
        }

        // MARK: - Actions - Outline

        /// Pinned tabs in order; saved tabs outside folders, then each folder
        /// with its folders and tabs unless it is collapsed; current tabs in
        /// order. A run of two or more tabs of one split is one row, and a
        /// Start Page shows no row.
        private static func sections(of space: SpaceModel) -> [Section] {
            let tabs = space.tabs.models.filter { $0.url != nil || $0.nativeContent != nil }
            let folders = space.folders.models
            return [TabPlacement.pinned, .saved, .current].map { placement in
                let placed = tabs.filter { $0.placement == placement }
                guard placement.holdsFolders else {
                    return Section(
                        placement: placement, rows: rows(of: placed, depth: 0, splits: placement.holdsSplits))
                }
                var rows = rows(of: placed.filter { $0.folderID == nil }, depth: 0, splits: placement.holdsSplits)
                appendFolders(
                    in: nil, depth: 0, placement: placement, folders: folders, tabs: placed, to: &rows)
                return Section(placement: placement, rows: rows)
            }
        }

        private static func appendFolders(
            in parentID: UUID?, depth: Int, placement: TabPlacement, folders: [FolderStateModel],
            tabs: [TabStateModel], to rows: inout [Row]
        ) {
            for folder in folders where folder.location == placement && folder.parentID == parentID {
                rows.append(Row(id: folder.id, kind: .folder, depth: depth, members: []))
                guard !folder.isCollapsed else { continue }
                appendFolders(
                    in: folder.id, depth: depth + 1, placement: placement, folders: folders, tabs: tabs, to: &rows)
                rows += Self.rows(
                    of: tabs.filter { $0.folderID == folder.id }, depth: depth + 1, splits: placement.holdsSplits)
            }
        }

        private static func rows(of tabs: [TabStateModel], depth: Int, splits: Bool) -> [Row] {
            var rows: [Row] = []
            var index = tabs.startIndex
            while index < tabs.endIndex {
                let tab = tabs[index]
                var end = index + 1
                if splits, let groupID = tab.splitGroupID {
                    while end < tabs.endIndex, tabs[end].splitGroupID == groupID { end += 1 }
                }
                if end - index >= 2, let groupID = tab.splitGroupID {
                    rows.append(Row(id: groupID, kind: .split, depth: depth, members: tabs[index..<end].map(\.id)))
                } else {
                    end = index + 1
                    rows.append(Row(id: tab.id, kind: .tab, depth: depth, members: [tab.id]))
                }
                index = end
            }
            return rows
        }
    }

    extension ReadModelSpikeOutline: BrowserStoreFirstObservable {}
#endif

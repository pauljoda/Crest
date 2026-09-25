#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: the rows of one list the
    /// core publishes, a section's top level or a folder's inside. It reads
    /// only that list, the objects its rows stand for and which page each
    /// tab has, and hands each row its objects, so a move redraws only the
    /// list it moves within and a row redraws only for what it shows.
    struct ReadModelSpikeRows: View {
        // MARK: - Types

        /// One row the list shows, with the inputs it hands that row.
        struct Item: Equatable, Identifiable {
            enum Content {
                case tab(TabStateModel, page: PageStateModel?)
                case folder(FolderStateModel)
                case split(ReadModelSpikeSplitRow.Members)
            }

            let id: UUID
            let content: Content
            let depth: Int

            /// Items are equal when they hand their row the same objects and
            /// values, as SwiftUI compares a view's inputs.
            static func == (lhs: Item, rhs: Item) -> Bool {
                guard lhs.id == rhs.id, lhs.depth == rhs.depth else { return false }
                switch (lhs.content, rhs.content) {
                case (.tab(let tab, let page), .tab(let other, let otherPage)):
                    return tab === other && page === otherPage
                case (.folder(let folder), .folder(let other)):
                    return folder === other
                case (.split(let members), .split(let other)):
                    return members == other
                default:
                    return false
                }
            }
        }

        // MARK: - Variables

        let list: SidebarListModel
        let space: SpaceModel
        let window: WindowStateModel
        let state: CoreState

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.section)
            #endif
            ForEach(Self.items(list: list, space: space, state: state)) { item in
                switch item.content {
                case .tab(let tab, let page):
                    ReadModelSpikeTabRow(
                        tab: tab, page: page, window: window, depth: item.depth, favicons: state.favicons)
                case .folder(let folder):
                    ReadModelSpikeFolderRow(
                        folder: folder, depth: item.depth, space: space, window: window, state: state)
                case .split(let members):
                    ReadModelSpikeSplitRow(
                        members: members, window: window, depth: item.depth, favicons: state.favicons)
                }
            }
        }

        // MARK: - Actions - Reading

        /// Everything the list's body reads, as the rows it shows. A row whose
        /// object the read model does not hold yet shows nothing until it does.
        @MainActor
        static func items(list: SidebarListModel, space: SpaceModel, state: CoreState) -> [Item] {
            var pages: [UUID: PageStateModel] = [:]
            for page in state.pages.values where page.spaceID == space.id {
                if let tabID = page.tabID { pages[tabID] = page }
            }
            return list.rows.compactMap { row in
                if row.kind.opensList {
                    return space.folders.model(row.id).map { Item(id: row.id, content: .folder($0), depth: row.depth) }
                }
                if row.kind.groupsTabs {
                    let members = row.members.compactMap { space.tabs.model($0) }
                    return Item(
                        id: row.id, content: .split(ReadModelSpikeSplitRow.Members(tabs: members)), depth: row.depth)
                }
                return space.tabs.model(row.id).map {
                    Item(id: row.id, content: .tab($0, page: pages[row.id]), depth: row.depth)
                }
            }
        }
    }
#endif

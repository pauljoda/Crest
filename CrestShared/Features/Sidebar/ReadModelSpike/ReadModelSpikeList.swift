#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: one Space's sidebar list
    /// over the read model. It reads the outline, the tab this window shows and
    /// which page each tab has, and hands each row its objects and whether it
    /// is selected, so a row redraws only for what it shows.
    struct ReadModelSpikeList: View {
        // MARK: - Types

        /// One view the list shows, with the inputs it hands that view.
        struct Item: Equatable, Identifiable {
            enum Content {
                case header(TabPlacement, isExpanded: Bool)
                case tab(TabStateModel, page: PageStateModel?)
                case folder(FolderStateModel)
                case split(ReadModelSpikeSplitRow.Members)
            }

            let id: String
            let content: Content
            let depth: Int
            let isSelected: Bool

            /// Items are equal when they hand their view the same objects and
            /// values, as SwiftUI compares a view's inputs.
            static func == (lhs: Item, rhs: Item) -> Bool {
                guard lhs.id == rhs.id, lhs.depth == rhs.depth, lhs.isSelected == rhs.isSelected else { return false }
                switch (lhs.content, rhs.content) {
                case (.header(let placement, let isExpanded), .header(let other, let otherIsExpanded)):
                    return placement == other && isExpanded == otherIsExpanded
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

        let space: SpaceModel
        let window: WindowStateModel
        let outline: ReadModelSpikeOutline
        let state: CoreState
        /// Whether rows are made only as they scroll into view, as the Mac
        /// sidebar makes them, or all at once, as the iPad's does.
        var isLazy = true

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.list)
            #endif
            let items = Self.items(space: space, window: window, outline: outline, state: state)
            ScrollView {
                if isLazy {
                    LazyVStack(alignment: .leading, spacing: 2) { rows(items) }
                } else {
                    VStack(alignment: .leading, spacing: 2) { rows(items) }
                }
            }
        }

        private func rows(_ items: [Item]) -> some View {
            ForEach(items) { item in
                switch item.content {
                case .header(let placement, let isExpanded):
                    ReadModelSpikeSectionHeader(placement: placement, isExpanded: isExpanded)
                case .tab(let tab, let page):
                    ReadModelSpikeTabRow(
                        tab: tab, page: page, isSelected: item.isSelected, depth: item.depth, favicons: state.favicons)
                case .folder(let folder):
                    ReadModelSpikeFolderRow(folder: folder, depth: item.depth)
                case .split(let members):
                    ReadModelSpikeSplitRow(
                        members: members, isSelected: item.isSelected, depth: item.depth, favicons: state.favicons)
                }
            }
        }

        // MARK: - Actions - Reading

        /// Everything the list's body reads, as the items it shows.
        @MainActor
        static func items(
            space: SpaceModel, window: WindowStateModel, outline: ReadModelSpikeOutline, state: CoreState
        ) -> [Item] {
            let shownTabID = window.shownTabs.first { $0.spaceID == space.id }?.tabID
            var pages: [UUID: PageStateModel] = [:]
            for page in state.pages.values where page.spaceID == space.id {
                if let tabID = page.tabID { pages[tabID] = page }
            }
            let isSavedExpanded = space.settings.isSavedTabsExpanded
            var items: [Item] = []
            for section in outline.sections {
                let isExpanded = section.placement != .saved || isSavedExpanded
                items.append(
                    Item(
                        id: "section-\(section.placement.name)",
                        content: .header(section.placement, isExpanded: isExpanded),
                        depth: 0, isSelected: false))
                guard isExpanded else { continue }
                for row in section.rows {
                    switch row.kind {
                    case .tab:
                        guard let tab = space.tabs.model(row.id) else { continue }
                        items.append(
                            Item(
                                id: "tab-\(row.id)", content: .tab(tab, page: pages[row.id]), depth: row.depth,
                                isSelected: row.id == shownTabID))
                    case .folder:
                        guard let folder = space.folders.model(row.id) else { continue }
                        items.append(
                            Item(id: "folder-\(row.id)", content: .folder(folder), depth: row.depth, isSelected: false))
                    case .split:
                        let members = row.members.compactMap { space.tabs.model($0) }
                        items.append(
                            Item(
                                id: "split-\(row.id)", content: .split(ReadModelSpikeSplitRow.Members(tabs: members)),
                                depth: row.depth, isSelected: shownTabID.map(row.members.contains) ?? false))
                    }
                }
            }
            return items
        }
    }
#endif

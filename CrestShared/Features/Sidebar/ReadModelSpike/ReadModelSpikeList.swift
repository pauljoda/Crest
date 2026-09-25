#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: one Space's sidebar list
    /// over the read model. It reads only whether each section is expanded,
    /// and hands each expanded section the list the core publishes for it, so
    /// a move, a collapse or another shown tab never redraws it.
    struct ReadModelSpikeList: View {
        // MARK: - Types

        /// One section the list shows, with the inputs it hands its header.
        struct Section: Equatable, Identifiable {
            let placement: TabPlacement
            let isExpanded: Bool

            var id: Int { placement.tag }
        }

        // MARK: - Variables

        let space: SpaceModel
        let window: WindowStateModel
        let state: CoreState
        /// Whether rows are made only as they scroll into view, as the Mac
        /// sidebar makes them, or all at once, as the iPad's does.
        var isLazy = true

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.list)
            #endif
            let sections = Self.sections(space: space)
            ScrollView {
                if isLazy {
                    LazyVStack(alignment: .leading, spacing: 2) { content(sections) }
                } else {
                    VStack(alignment: .leading, spacing: 2) { content(sections) }
                }
            }
        }

        private func content(_ sections: [Section]) -> some View {
            ForEach(sections) { section in
                ReadModelSpikeSectionHeader(placement: section.placement, isExpanded: section.isExpanded)
                if section.isExpanded {
                    ReadModelSpikeRows(
                        list: space.sidebar.section(section.placement), space: space, window: window, state: state)
                }
            }
        }

        // MARK: - Actions - Reading

        /// Everything the list's body reads, as the sections it shows.
        @MainActor
        static func sections(space: SpaceModel) -> [Section] {
            let isSavedExpanded = space.settings.isSavedTabsExpanded
            return TabPlacement.all.map { Section(placement: $0, isExpanded: $0 != .saved || isSavedExpanded) }
        }
    }
#endif

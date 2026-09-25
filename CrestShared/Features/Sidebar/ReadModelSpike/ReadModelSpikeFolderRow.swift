#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: a folder's sidebar row,
    /// and while it is expanded, the rows of its inside. A collapse redraws
    /// this row alone; the rows of its inside come and go with it.
    struct ReadModelSpikeFolderRow: View {
        // MARK: - Types

        /// Everything the row's body reads.
        struct Shown: Equatable {
            let title: String
            let symbol: String
            let color: BrandColor
            let isCollapsed: Bool

            @MainActor
            init(folder: FolderStateModel) {
                title = folder.title
                symbol = folder.displaySymbol
                color = folder.displayColor
                isCollapsed = folder.isCollapsed
            }
        }

        // MARK: - Variables

        let folder: FolderStateModel
        let depth: Int
        let space: SpaceModel
        let window: WindowStateModel
        let state: CoreState

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.row)
            #endif
            let shown = Shown(folder: folder)
            HStack(spacing: 6) {
                Image(systemName: shown.isCollapsed ? "chevron.right" : "chevron.down").font(.caption2)
                Image(systemName: shown.symbol)
                    .foregroundStyle(Color(red: shown.color.red, green: shown.color.green, blue: shown.color.blue))
                Text(shown.title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 12)
            .padding(.vertical, 3)
            if !shown.isCollapsed {
                ReadModelSpikeRows(list: space.sidebar.inside(folder.id), space: space, window: window, state: state)
            }
        }
    }
#endif

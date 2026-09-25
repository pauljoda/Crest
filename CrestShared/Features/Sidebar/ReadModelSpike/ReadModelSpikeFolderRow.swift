#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: a folder's sidebar row.
    struct ReadModelSpikeFolderRow: View {
        // MARK: - Types

        /// Everything the row's body reads.
        struct Shown: Equatable {
            let title: String
            let symbol: String?
            let color: BrandColor?
            let isCollapsed: Bool

            @MainActor
            init(folder: FolderStateModel) {
                title = folder.title
                symbol = folder.symbol
                color = folder.color
                isCollapsed = folder.isCollapsed
            }
        }

        // MARK: - Variables

        let folder: FolderStateModel
        let depth: Int

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.row)
            #endif
            let shown = Shown(folder: folder)
            HStack(spacing: 6) {
                Image(systemName: shown.isCollapsed ? "chevron.right" : "chevron.down").font(.caption2)
                Image(systemName: shown.symbol ?? "folder.fill")
                    .foregroundStyle(
                        shown.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .secondary)
                Text(shown.title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 12)
            .padding(.vertical, 3)
        }
    }
#endif

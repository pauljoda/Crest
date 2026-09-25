#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: a split's sidebar row,
    /// one card per member, shown while its window shows any member.
    struct ReadModelSpikeSplitRow: View {
        // MARK: - Types

        /// The split's members, equal when they are the same objects, so a
        /// list that hands the row the same members again leaves it alone.
        struct Members: Equatable {
            let tabs: [TabStateModel]

            static func == (lhs: Members, rhs: Members) -> Bool {
                lhs.tabs.elementsEqual(rhs.tabs, by: ===)
            }
        }

        /// Everything the row's body reads.
        struct Shown: Equatable {
            let titles: [String]
            let symbols: [String]
            let images: [Data?]
            let isShown: Bool

            @MainActor
            init(members: Members, window: WindowStateModel, favicons: FaviconAssets) {
                titles = members.tabs.map(\.displayTitle)
                symbols = members.tabs.map(\.symbol)
                images = members.tabs.map { favicons.image(of: $0.id) }
                isShown = members.tabs.map { window.shownTabIDs.contains($0.id) }.contains(true)
            }
        }

        // MARK: - Variables

        let members: Members
        let window: WindowStateModel
        let depth: Int
        let favicons: FaviconAssets

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.row)
            #endif
            let shown = Shown(members: members, window: window, favicons: favicons)
            HStack(spacing: 4) {
                ForEach(shown.titles.indices, id: \.self) { index in
                    HStack(spacing: 4) {
                        Image(systemName: shown.images[index] == nil ? shown.symbols[index] : "photo")
                        Text(shown.titles[index]).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, CGFloat(depth) * 12)
            .padding(.vertical, 3)
            .background(shown.isShown ? Color.accentColor.opacity(0.2) : Color.clear, in: .rect(cornerRadius: 6))
        }
    }
#endif

#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: a tab's sidebar row. It
    /// reads only the fields it shows from its tab, its page, its image and
    /// whether its window shows it, so another shown tab redraws two rows.
    struct ReadModelSpikeTabRow: View {
        // MARK: - Types

        /// Everything the row's body reads.
        struct Shown: Equatable {
            let title: String
            let symbol: String
            let image: Data?
            let host: String?
            let isAwayFromSavedAddress: Bool
            let isLoading: Bool
            let isShown: Bool

            @MainActor
            init(tab: TabStateModel, page: PageStateModel?, window: WindowStateModel, favicons: FaviconAssets) {
                title = tab.displayTitle
                symbol = tab.symbol
                image = favicons.image(of: tab.id)
                host = tab.url.flatMap { URL(string: $0)?.host() }
                isAwayFromSavedAddress = tab.isAwayFromSavedAddress
                isLoading = page?.live.isLoading ?? false
                isShown = window.shownTabIDs.contains(tab.id)
            }
        }

        // MARK: - Variables

        let tab: TabStateModel
        let page: PageStateModel?
        let window: WindowStateModel
        let depth: Int
        let favicons: FaviconAssets

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.row)
            #endif
            let shown = Shown(tab: tab, page: page, window: window, favicons: favicons)
            HStack(spacing: 6) {
                Image(systemName: shown.image == nil ? shown.symbol : "photo")
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(shown.title).lineLimit(1)
                    if let host = shown.host {
                        Text(host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if shown.isAwayFromSavedAddress { Image(systemName: "arrow.uturn.backward").font(.caption2) }
                if shown.isLoading { ProgressView().controlSize(.mini) }
            }
            .padding(.leading, CGFloat(depth) * 12)
            .padding(.vertical, 3)
            .background(shown.isShown ? Color.accentColor.opacity(0.2) : Color.clear, in: .rect(cornerRadius: 6))
        }
    }
#endif

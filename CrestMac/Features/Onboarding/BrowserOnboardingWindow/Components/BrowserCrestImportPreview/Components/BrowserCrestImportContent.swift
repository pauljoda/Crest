import SwiftUI

struct BrowserCrestImportContent: View {
    let space: BrowserSpace
    let matchedTabIDs: Set<TabID>
    @Environment(CrestCore.self) private var core: CrestCore?

    /// No window shows an imported Space yet, so it highlights the tab the
    /// core would show first.
    private var highlightedTabID: TabID? { core?.fallbackTabID(in: space) }

    var body: some View {
        VStack(spacing: 0) {
            BrowserCrestImportChrome(space: space, highlightedTabID: highlightedTabID)

            if !space.pinnedTabs.isEmpty {
                BrowserCrestImportPinnedGrid(
                    space: space,
                    matchedTabIDs: matchedTabIDs,
                    highlightedTabID: highlightedTabID
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            BrowserCrestImportSpaceHeader(space: space)
            BrowserCrestImportTabList(
                space: space,
                matchedTabIDs: matchedTabIDs,
                highlightedTabID: highlightedTabID
            )
            BrowserCrestImportSpaceSwitcher(space: space)
        }
    }
}

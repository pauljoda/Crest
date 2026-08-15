import SwiftUI

struct BrowserCrestImportContent: View {
    let space: BrowserSpace
    let matchedTabIDs: Set<TabID>

    var body: some View {
        VStack(spacing: 0) {
            BrowserCrestImportChrome(space: space)

            if !space.pinnedTabs.isEmpty {
                BrowserCrestImportPinnedGrid(
                    space: space,
                    matchedTabIDs: matchedTabIDs
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            BrowserCrestImportSpaceHeader(space: space)
            BrowserCrestImportTabList(
                space: space,
                matchedTabIDs: matchedTabIDs
            )
            BrowserCrestImportSpaceSwitcher(space: space)
        }
    }
}

#Preview("Crest Import Content") {
    BrowserCrestImportContent(
        space: BrowserImportPreviewFixture.sourceSpace,
        matchedTabIDs: [BrowserImportPreviewFixture.pinnedTab.id]
    )
    .frame(width: 340, height: 620)
}

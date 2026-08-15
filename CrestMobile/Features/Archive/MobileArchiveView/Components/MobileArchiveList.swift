import SwiftUI

struct MobileArchiveList: View {
    let space: BrowserSpace?
    let restoreArchivedTab: (TabID) -> Void

    var body: some View {
        Group {
            if let space {
                BrowserUtilityListContent(
                    surface: .archive,
                    space: space,
                    downloads: [],
                    searchText: "",
                    filter: .all,
                    actions: BrowserUtilityListActions(
                        restoreArchivedTab: { tabID, _ in
                            restoreArchivedTab(tabID)
                        }
                    )
                )
            } else {
                ContentUnavailableView(
                    "No Space",
                    systemImage: "square.grid.2x2"
                )
            }
        }
    }
}

#Preview {
    let fixture = MobileBrowserPreviewFixture()
    MobileArchiveList(space: fixture.space, restoreArchivedTab: { _ in })
}

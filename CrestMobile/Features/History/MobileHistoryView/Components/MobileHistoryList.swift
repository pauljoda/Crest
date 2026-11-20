import SwiftUI

struct MobileHistoryList: View {
    let space: SpaceModel?
    let searchText: String
    let openHistoryEntry: (HistoryEntryState) -> Void

    var body: some View {
        Group {
            if let space {
                BrowserUtilityListContent(
                    surface: .history,
                    space: space,
                    downloads: [],
                    searchText: searchText,
                    filter: .all,
                    actions: BrowserUtilityListActions(
                        openHistoryEntry: { entry, _ in
                            openHistoryEntry(entry)
                        }
                    )
                )
            } else {
                ContentUnavailableView {
                    Label {
                        Text("No Space").font(CrestTypography.displayPage)
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            }
        }
    }
}

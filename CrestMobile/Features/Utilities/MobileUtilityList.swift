import SwiftUI

/// A Space's history, archive or downloads in a sheet on iPhone and iPad: the
/// shared list for `surface`, or no Space when the Space is gone or locked.
struct MobileUtilityList: View {
    // MARK: - Variables

    let surface: BrowserUtilitySurface
    let space: SpaceModel?
    var downloads: [DownloadState] = []
    var searchText = ""
    let actions: BrowserUtilityListActions
    var favicons: FaviconAssets?

    var body: some View {
        if let space {
            BrowserUtilityListContent(
                surface: surface, space: space, downloads: downloads, searchText: searchText, filter: .all,
                actions: actions, favicons: favicons)
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

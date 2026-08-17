import SwiftUI

struct MobileBrowserSidebarPager: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        ZStack {
            if configuration.mode == .compactTabViewer {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            }

            BrowserSpacePager(
                spaces: BrowserSidebarAccessPolicy.availableSpaces(
                    in: configuration.browser
                ),
                selectedSpaceID: configuration.browser.session.selectedSpaceID,
                isInteractionLocked: configuration.browser.tabDragState.item != nil
                    || configuration.browser.folderDragState.item != nil,
                selectSpace: configuration.selectSpace,
                settledSpace: configuration.settleSpaceSelection
            ) { space, isSelected in
                MobileBrowserSidebarSpaceSurface(
                    configuration: configuration,
                    space: space,
                    isSelected: isSelected
                )
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                MobileBrowserSidebarChrome(configuration: configuration)
            }
        }
    }
}

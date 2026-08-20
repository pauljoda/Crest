import SwiftUI

struct MobileBrowserSidebarPager: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        ZStack {
            if configuration.showsPageBackdrop {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            }

            BrowserSidebarSpacePager(
                context: configuration.context
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

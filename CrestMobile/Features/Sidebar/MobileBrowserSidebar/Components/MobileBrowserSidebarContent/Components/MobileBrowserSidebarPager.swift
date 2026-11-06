import SwiftUI

struct MobileBrowserSidebarPager: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                MobileBrowserSidebarChrome(configuration: configuration)
                    .fixedSize(horizontal: false, vertical: true)
                    // The chrome's refusal label hangs below its bounds, over the
                    // pager. Drawing the chrome later keeps the label visible;
                    // the label takes no hits, so the pages keep theirs.
                    .zIndex(1)
                BrowserSidebarSpacePager(context: configuration.context) { space, isSelected in
                    MobileBrowserSidebarSpaceSurface(configuration: configuration, space: space, isSelected: isSelected)
                }
            }
        }
        .background {
            if configuration.showsPageBackdrop {
                SpaceBackdropBlend(
                    spaces: configuration.context.availableSpaces,
                    selectedSpace: configuration.context.browser.shownSpace
                ) { space in
                    if let space {
                        BrowserSpaceBannerBackground(branding: space.settings.look)
                    } else {
                        Color(uiColor: .systemBackground)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}

import SwiftUI

struct MobileBrowserSidebarChrome: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        VStack(spacing: 0) {
            MobileBrowserSidebarTopChrome(configuration: configuration)

            MobileSpacePicker(
                browser: configuration.browser,
                pages: configuration.pages,
                spaceAccess: configuration.spaceAccess,
                selectSpace: configuration.selectSpace
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }
}

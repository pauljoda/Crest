import SwiftUI

struct MobileBrowserSidebarContent: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        if #available(iOS 27.0, *) {
            MobileBrowserSidebarLayout(configuration: configuration)
        } else {
            MobileBrowserSidebarLayout(configuration: configuration)
                .gesture(
                    MobileDragReleaseGesture {
                        configuration.browser.tabDragState.endAfterTouchRelease()
                        configuration.browser.folderDragState.endAfterTouchRelease()
                    }
                )
        }
    }
}

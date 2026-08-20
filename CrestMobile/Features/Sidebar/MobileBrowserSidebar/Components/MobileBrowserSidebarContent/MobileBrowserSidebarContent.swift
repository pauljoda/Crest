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
                        configuration.context.browser.tabDragState
                            .endAfterTouchRelease()
                        configuration.context.browser.folderDragState
                            .endAfterTouchRelease()
                    }
                )
        }
    }
}

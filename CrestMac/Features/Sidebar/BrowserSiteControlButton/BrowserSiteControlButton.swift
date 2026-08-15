import SwiftUI

struct BrowserSiteControlButton: View {
    let configuration: BrowserSiteControlConfiguration

    @State private var isPresented = false

    var body: some View {
        BrowserSiteControlTrigger(isPresented: $isPresented)
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                BrowserSiteControlPopover(
                    configuration: configuration,
                    dismiss: { isPresented = false }
                )
            }
    }
}

#Preview("Site Control Button") {
    let preview = BrowserSidebarExtensionPreviewFixture.makeContext()
    BrowserSiteControlButton(configuration: preview.configuration)
        .padding()
}

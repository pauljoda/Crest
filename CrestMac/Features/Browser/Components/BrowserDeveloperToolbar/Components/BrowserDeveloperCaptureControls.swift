import SwiftUI

struct BrowserDeveloperCaptureControls: View {
    let page: BrowserPage
    @Binding var showsCaptureOptions: Bool

    var body: some View {
        HStack(spacing: BrowserDeveloperToolbarMetrics.itemSpacing) {
            BrowserDeveloperToolbarButton(
                label: "Capture Window",
                systemImage: "rectangle.inset.filled",
                isActive: showsCaptureOptions,
                action: { showsCaptureOptions.toggle() }
            )
            .popover(isPresented: $showsCaptureOptions, arrowEdge: .top) {
                BrowserDeveloperCaptureOptions(page: page)
            }

            BrowserDeveloperToolbarButton(
                label: "Capture",
                systemImage: "camera",
                isActive: page.isRegionCapturePresented,
                action: page.beginRegionCapture
            )
        }
    }
}

#Preview("Developer Capture Controls") {
    @Previewable @State var showsCaptureOptions = false
    let preview = BrowserDetailPreviewFixture.makeWebContent()
    BrowserDeveloperCaptureControls(
        page: preview.page,
        showsCaptureOptions: $showsCaptureOptions
    )
    .padding()
}

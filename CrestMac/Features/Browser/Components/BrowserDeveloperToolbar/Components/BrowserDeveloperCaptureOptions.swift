import SwiftUI

struct BrowserDeveloperCaptureOptions: View {
    let page: BrowserPage

    var body: some View {
        VStack(spacing: 12) {
            BrowserDeveloperCapturePreview()
            Button(
                "Capture in Portrait Mode",
                systemImage: "rectangle.portrait.on.rectangle.portrait"
            ) {
                page.savePortraitCapture()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            Button(
                "Copy Full Page Capture",
                systemImage: "doc.on.clipboard"
            ) {
                page.copyFullPageCapture()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: 260)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture Window")
    }
}

#Preview("Developer Capture Options") {
    let preview = BrowserDetailPreviewFixture.makeWebContent()
    BrowserDeveloperCaptureOptions(page: preview.page)
}

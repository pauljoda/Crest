import SwiftUI

struct BrowserDeveloperInspectorControls: View {
    let page: BrowserPage

    var body: some View {
        HStack(spacing: BrowserDeveloperToolbarMetrics.itemSpacing) {
            BrowserDeveloperToolbarButton(
                label: "Toggle Console",
                systemImage: "apple.terminal",
                isActive: page.developerPanel == .console,
                action: { page.toggleDeveloperPanel(.console) }
            )
            BrowserDeveloperToolbarButton(
                label: "Toggle Network Panel",
                systemImage: "network",
                isActive: page.developerPanel == .network,
                action: { page.toggleDeveloperPanel(.network) }
            )
            BrowserDeveloperToolbarButton(
                label: "Inspect Element",
                systemImage: "scope",
                isActive: page.developerPanel == .elements,
                action: { page.toggleDeveloperPanel(.elements) }
            )
        }
    }
}

#Preview("Developer Inspector Controls") {
    let preview = BrowserDetailPreviewFixture.makeWebContent()
    BrowserDeveloperInspectorControls(page: preview.page)
        .padding()
}

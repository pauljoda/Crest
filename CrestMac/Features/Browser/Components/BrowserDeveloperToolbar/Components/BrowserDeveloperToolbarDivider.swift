import SwiftUI

struct BrowserDeveloperToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(height: BrowserDeveloperToolbarMetrics.dividerHeight)
            .padding(.horizontal, BrowserDeveloperToolbarMetrics.dividerPadding)
            .accessibilityHidden(true)
    }
}

#Preview("Developer Toolbar Divider") {
    BrowserDeveloperToolbarDivider()
        .padding()
}

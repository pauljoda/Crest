import SwiftUI

struct BrowserSiteQuickActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: BrowserSiteControlMetrics.quickActionGlyphSize,
                        weight: .medium
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: BrowserSiteControlMetrics.quickActionHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSiteQuickActionButton(title: "Site Settings", systemImage: "gearshape", action: {}).padding()
    }
#endif

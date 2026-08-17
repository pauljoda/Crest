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
                        size: BrowserSiteControlLayoutPolicy.quickActionGlyphSize,
                        weight: .medium
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: BrowserSiteControlLayoutPolicy.quickActionHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}

import SwiftUI

struct BrowserSpaceEditorIdentityPreview: View {
    let branding: BrowserSpaceBranding
    let symbol: String

    var body: some View {
        Group {
            if branding.iconStyle == .layeredCrest {
                BrowserSpaceCrestIcon(
                    branding: branding,
                    size: BrowserSpaceForgeMetrics.previewIdentitySize
                )
            } else {
                if let emoji = BrowserIconSymbol.emoji(from: symbol) {
                    Text(emoji)
                        .font(.title2)
                        .frame(
                            width: BrowserSpaceForgeMetrics.previewIdentitySize,
                            height: BrowserSpaceForgeMetrics.previewIdentitySize
                        )
                } else {
                    Image(systemName: symbol)
                        .font(
                            .system(
                                size: BrowserSpaceForgeMetrics.previewSymbolPointSize,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(branding.primaryColor.color)
                        .frame(
                            width: BrowserSpaceForgeMetrics.previewIdentitySize,
                            height: BrowserSpaceForgeMetrics.previewIdentitySize
                        )
                }
            }
        }
    }
}

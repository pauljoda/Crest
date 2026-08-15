import SwiftUI

struct BrowserSpaceCrestBackplateMask: View {
    let systemImage: String
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.72, weight: .regular))
            .frame(width: size, height: size)
    }
}

#Preview("Crest Backplate Mask", traits: .sizeThatFitsLayout) {
    let branding = BrowserSpaceBrandingPreviewFixture.crestBranding

    BrowserSpaceCrestBackplateMask(
        systemImage: branding.crest.backplate.systemImage ?? "shield.fill",
        size: 112
    )
    .foregroundStyle(branding.primaryColor.color)
    .padding()
}

import SwiftUI

struct BrowserImportSidebarFrame<Content: View>: View {
    let branding: BrowserSpaceBranding
    let content: Content

    init(
        branding: BrowserSpaceBranding,
        @ViewBuilder content: () -> Content
    ) {
        self.branding = branding
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { BrowserSpaceBannerBackground(branding: branding) }
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
            }
            .environment(
                \.colorScheme,
                BrowserSpaceForegroundPolicy.colorScheme(for: branding)
            )
    }
}

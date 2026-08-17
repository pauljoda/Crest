import SwiftUI

/// Live sidebar context for the Space branding being edited.
struct BrowserSpaceEditorPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let branding: BrowserSpaceBranding
    let symbol: String
    let compact: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            BrowserSpaceBannerBackground(branding: branding)

            VStack(spacing: CrestSpacing.small) {
                RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous)
                    .fill(.thinMaterial)
                    .frame(height: BrowserSpaceForgeMetrics.previewSearchFieldHeight)
                    .overlay(alignment: .leading) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(CrestColor.textSecondary)
                            .padding(.leading, CrestSpacing.medium)
                    }

                Spacer()

                HStack {
                    BrowserSpaceEditorIdentityPreview(
                        branding: branding,
                        symbol: symbol
                    )
                    Spacer()
                    Image(systemName: "plus")
                        .foregroundStyle(CrestColor.textPrimary)
                }
            }
            .padding(CrestSpacing.medium)
        }
        .frame(
            maxWidth: compact
                ? .infinity
                : BrowserSpaceForgeMetrics.previewMaximumWidth
        )
        .frame(
            height: compact
                ? BrowserSpaceForgeMetrics.compactPreviewHeight
                : BrowserSpaceForgeMetrics.previewHeight
        )
        .clipShape(.rect(cornerRadius: CrestRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CrestRadius.card, style: .continuous)
                .strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline)
        }
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.pane,
                reduceMotion: reduceMotion
            ),
            value: branding
        )
        .accessibilityLabel("Live Space sidebar preview")
        .accessibilityIdentifier("space-branding-editor-preview")
    }
}

import SwiftUI

/// The bar a page wears while it offers to reload its document in WebKit for
/// protected video its own engine cannot play. Reload moves the page as the
/// automatic switch would; the close button keeps it where it is for this
/// document. It sits with the engine's own bars, in the same glass.
struct BrowserProtectedMediaPageBar: View {
    let reload: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: BrowserWebPageSurfaceMetrics.infoBarSpacing) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(
                "This site’s video needs WebKit to play.",
                comment: "The bar on a page whose protected video plays only in WebKit."
            )
            .font(.callout)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(
                String(
                    localized: "Reload in WebKit",
                    comment: "Reloads a page in WebKit so its protected video plays."),
                action: reload
            )
            .buttonStyle(.borderedProminent)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Dismiss"))
        }
        .controlSize(.small)
        .padding(.horizontal, BrowserWebPageSurfaceMetrics.infoBarHorizontalPadding)
        .padding(.vertical, BrowserWebPageSurfaceMetrics.infoBarVerticalPadding)
        .frame(maxWidth: BrowserWebPageSurfaceMetrics.infoBarMaximumWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: BrowserWebPageSurfaceMetrics.infoBarCornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protected-media-page-bar")
    }
}

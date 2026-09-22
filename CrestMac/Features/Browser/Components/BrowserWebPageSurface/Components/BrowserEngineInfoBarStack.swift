import SwiftUI

/// The engine's bars for this page, stacked at its top edge.
struct BrowserEngineInfoBarStack: View {
    let page: BrowserPage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: BrowserWebPageSurfaceMetrics.infoBarSpacing) {
            ForEach(page.engineInfoBars) { bar in
                BrowserEngineInfoBarRow(bar: bar) { response in
                    page.respond(to: bar, with: response)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(BrowserWebPageSurfaceMetrics.overlayPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : CrestMotion.feedbackPresentation, value: page.engineInfoBars)
    }
}

private struct BrowserEngineInfoBarRow: View {
    let bar: BrowserEngineInfoBar
    let respond: (BrowserEngineInfoBar.Response) -> Void

    var body: some View {
        HStack(spacing: BrowserWebPageSurfaceMetrics.infoBarSpacing) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(bar.message)
                .font(.callout)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !bar.cancelTitle.isEmpty {
                Button(bar.cancelTitle) { respond(.cancel) }
            }
            if !bar.acceptTitle.isEmpty {
                Button(bar.acceptTitle) { respond(.accept) }
                    .buttonStyle(.borderedProminent)
            }
            if bar.isCloseable {
                Button {
                    respond(.dismiss)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Dismiss"))
            }
        }
        .controlSize(.small)
        .padding(.horizontal, BrowserWebPageSurfaceMetrics.infoBarHorizontalPadding)
        .padding(.vertical, BrowserWebPageSurfaceMetrics.infoBarVerticalPadding)
        .frame(maxWidth: BrowserWebPageSurfaceMetrics.infoBarMaximumWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: BrowserWebPageSurfaceMetrics.infoBarCornerRadius))
        .accessibilityElement(children: .contain)
    }
}

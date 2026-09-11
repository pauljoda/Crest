import SwiftUI

struct BrowserCommandPalettePresentationView: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let morphID: String?
    let overlayContentLeadingInset: CGFloat
    var overlayContentInsets: EdgeInsets? = nil
    let queryIsFocused: FocusState<Bool>.Binding

    @ViewBuilder
    var body: some View {
        if presentation == .overlay {
            GeometryReader { proxy in
                let availableHeight =
                    proxy.size.height - (overlayContentInsets?.top ?? 0) - (overlayContentInsets?.bottom ?? 0)
                let maximumResultAreaHeight =
                    BrowserCommandPaletteLayout
                    .overlayResultAreaHeight(availableHeight: availableHeight)

                ZStack {
                    BrowserCommandPaletteScrim(dismiss: model.dismiss)
                    BrowserCommandPaletteCard(
                        model: model,
                        presentation: presentation,
                        maximumResultAreaHeight: maximumResultAreaHeight,
                        morphNamespace: morphNamespace,
                        morphID: morphID,
                        queryIsFocused: queryIsFocused
                    )
                    .padding(BrowserCommandPaletteMetrics.overlayCardPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(
                        overlayContentInsets
                            ?? EdgeInsets(top: 0, leading: overlayContentLeadingInset, bottom: 0, trailing: 0))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            BrowserCommandPaletteCard(
                model: model,
                presentation: presentation,
                maximumResultAreaHeight: BrowserCommandPaletteLayout.maximumResultAreaHeight,
                morphNamespace: morphNamespace,
                morphID: morphID,
                queryIsFocused: queryIsFocused
            )
        }
    }
}

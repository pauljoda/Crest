import SwiftUI

struct BrowserCommandPalettePresentationView: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let morphID: String?
    let queryIsFocused: FocusState<Bool>.Binding

    @ViewBuilder
    var body: some View {
        if presentation == .overlay {
            GeometryReader { proxy in
                let availableHeight = proxy.size.height
                let maximumResultAreaHeight =
                    BrowserCommandPaletteLayout
                    .overlayResultAreaHeight(availableHeight: availableHeight)

                ZStack(alignment: .top) {
                    BrowserCommandPaletteScrim(dismiss: model.dismiss)
                    BrowserCommandPaletteCard(
                        model: model,
                        presentation: presentation,
                        maximumResultAreaHeight: maximumResultAreaHeight,
                        morphNamespace: morphNamespace,
                        morphID: morphID,
                        queryIsFocused: queryIsFocused
                    )
                    .padding(.horizontal, BrowserCommandPaletteMetrics.overlayCardPadding)
                    .padding(
                        .top,
                        BrowserCommandPaletteLayout.overlayCardTopInset(
                            availableHeight: availableHeight
                        )
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

#Preview("Command Palette Presentation — Overlay") {
    @Previewable @State var model = BrowserCommandPalettePreviewFixture.model(
        query: "swift"
    )
    @Previewable @FocusState var queryIsFocused: Bool

    ZStack {
        CrestBrandTheme.canvas
        BrowserCommandPalettePresentationView(
            model: model,
            presentation: .overlay,
            morphNamespace: nil,
            morphID: nil,
            queryIsFocused: $queryIsFocused
        )
    }
    .frame(width: 980, height: 720)
}

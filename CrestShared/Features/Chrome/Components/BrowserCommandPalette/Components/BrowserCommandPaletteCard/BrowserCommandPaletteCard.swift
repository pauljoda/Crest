import SwiftUI

struct BrowserCommandPaletteCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let maximumResultAreaHeight: CGFloat
    let morphNamespace: Namespace.ID?
    let morphID: String?
    let queryIsFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            BrowserCommandPaletteSearchField(
                model: model,
                presentation: presentation,
                queryIsFocused: queryIsFocused
            )

            if !model.resultGroups.isEmpty {
                Divider()
                BrowserCommandPaletteResultList(
                    model: model,
                    maximumResultAreaHeight: maximumResultAreaHeight
                )
            }
        }
        .frame(maxWidth: BrowserCommandPaletteMetrics.maximumCardWidth)
        .browserPaletteMorph(
            id: morphID,
            in: morphNamespace,
            reduceMotion: reduceMotion
        )
        .modifier(
            BrowserCommandPaletteShellMaterial(
                reduceTransparency: reduceTransparency
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("command-palette")
    }
}

#Preview("Command Palette Card") {
    @Previewable @State var model = BrowserCommandPalettePreviewFixture.model(
        query: "swift"
    )
    @Previewable @FocusState var queryIsFocused: Bool

    ZStack {
        CrestBrandTheme.canvas
        BrowserCommandPaletteCard(
            model: model,
            presentation: .overlay,
            maximumResultAreaHeight: BrowserCommandPaletteLayout.maximumResultAreaHeight,
            morphNamespace: nil,
            morphID: nil,
            queryIsFocused: $queryIsFocused
        )
        .padding(CrestSpacing.large)
    }
    .frame(width: 760, height: 560)
}

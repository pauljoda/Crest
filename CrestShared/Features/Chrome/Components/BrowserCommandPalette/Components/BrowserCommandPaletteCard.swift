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
        .clipShape(
            .rect(
                cornerRadius: BrowserCommandPaletteMetrics.cardCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("command-palette")
    }
}

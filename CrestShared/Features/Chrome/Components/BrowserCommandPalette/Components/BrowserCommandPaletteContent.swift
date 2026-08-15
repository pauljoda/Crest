import SwiftUI

struct BrowserCommandPaletteContent: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let morphID: String?

    @FocusState private var queryIsFocused: Bool

    var body: some View {
        BrowserCommandPalettePresentationView(
            model: model,
            presentation: presentation,
            morphNamespace: morphNamespace,
            morphID: morphID,
            queryIsFocused: $queryIsFocused
        )
        .task {
            await Task.yield()
            queryIsFocused = true
        }
        .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
        }
        .browserPaletteExitCommand(
            presentation == .overlay ? model.dismiss : {}
        )
    }
}

#Preview("Command Palette Content — Embedded") {
    @Previewable @State var model = BrowserCommandPalettePreviewFixture.model(
        query: "swift"
    )

    BrowserCommandPaletteContent(
        model: model,
        presentation: .embedded,
        morphNamespace: nil,
        morphID: nil
    )
    .padding(CrestSpacing.large)
    .frame(width: 760)
}

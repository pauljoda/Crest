import SwiftUI

struct BrowserCommandPaletteContent: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let morphID: String?
    let overlayContentLeadingInset: CGFloat

    @FocusState private var queryIsFocused: Bool

    var body: some View {
        BrowserCommandPalettePresentationView(
            model: model,
            presentation: presentation,
            morphNamespace: morphNamespace,
            morphID: morphID,
            overlayContentLeadingInset: overlayContentLeadingInset,
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

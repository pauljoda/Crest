import SwiftUI

struct BrowserCommandPaletteContent: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let morphID: String?
    let overlayContentLeadingInset: CGFloat
    var overlayContentInsets: EdgeInsets? = nil

    @FocusState private var queryIsFocused: Bool
    @Environment(\.spaceContentIsInteractive) private var spaceContentIsInteractive
    @Environment(\.isEnabled) private var isEnabled

    private var canFocus: Bool { isEnabled && spaceContentIsInteractive }

    var body: some View {
        BrowserCommandPalettePresentationView(
            model: model,
            presentation: presentation,
            morphNamespace: morphNamespace,
            morphID: morphID,
            overlayContentLeadingInset: overlayContentLeadingInset,
            overlayContentInsets: overlayContentInsets,
            queryIsFocused: $queryIsFocused
        )
        .task(id: canFocus) {
            guard canFocus else {
                queryIsFocused = false
                return
            }
            await Task.yield()
            guard !Task.isCancelled, canFocus else { return }
            queryIsFocused = true
        }
        .onKeyPress(.downArrow) {
            guard !model.completionEditing.isComposing else { return .ignored }
            model.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !model.completionEditing.isComposing else { return .ignored }
            model.moveSelection(by: -1)
            return .handled
        }
        .browserPaletteExitCommand(
            presentation == .overlay ? model.dismiss : {}
        )
    }
}

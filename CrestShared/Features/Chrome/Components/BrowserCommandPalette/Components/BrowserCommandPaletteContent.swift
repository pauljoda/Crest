import SwiftUI

struct BrowserCommandPaletteContent: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let overlayContentLeadingInset: CGFloat
    var overlayContentInsets: EdgeInsets? = nil
    var fieldFrame: CGRect? = nil

    @FocusState private var queryIsFocused: Bool
    @Environment(\.spaceContentIsInteractive) private var spaceContentIsInteractive
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.commandPaletteFocusesOnShow) private var focusesOnShow

    private var canFocus: Bool { isEnabled && spaceContentIsInteractive }

    var body: some View {
        BrowserCommandPalettePresentationView(
            model: model,
            presentation: presentation,
            morphNamespace: morphNamespace,
            overlayContentLeadingInset: overlayContentLeadingInset,
            overlayContentInsets: overlayContentInsets,
            fieldFrame: fieldFrame,
            queryIsFocused: $queryIsFocused
        )
        .task(id: canFocus) {
            guard canFocus else {
                queryIsFocused = false
                return
            }
            guard focusesOnShow else { return }
            await Task.yield()
            guard !Task.isCancelled, canFocus else { return }
            queryIsFocused = true
        }
        .onKeyPress(.downArrow) {
            guard !model.completionEditing.isComposing else { return .ignored }
            model.moveSelection(by: presentation.listsUpward ? -1 : 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !model.completionEditing.isComposing else { return .ignored }
            model.moveSelection(by: presentation.listsUpward ? 1 : -1)
            return .handled
        }
        .browserPaletteExitCommand(
            presentation.closesOnExit ? model.dismiss : {}
        )
    }
}

extension EnvironmentValues {
    /// Whether a command palette takes the keyboard as it shows, as a Start
    /// Page's does, ready for typing. A preview of a window that only shows
    /// what a person will get, such as setup's copy of the browser, leaves the
    /// palette waiting until it is clicked.
    @Entry var commandPaletteFocusesOnShow = true
}

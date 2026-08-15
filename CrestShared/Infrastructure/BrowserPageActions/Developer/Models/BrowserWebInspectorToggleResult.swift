enum BrowserWebInspectorToggleResult: Equatable, Sendable {
    case opened(BrowserDeveloperPanel)
    case closed
    case unavailable
}

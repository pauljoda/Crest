enum BrowserPagePresentation: CaseIterable, Equatable, Sendable {
    case noSelection
    case startPage
    case livePage
    case navigationFailure
    case processFailure
    case unloaded
    case automaticRestore
}

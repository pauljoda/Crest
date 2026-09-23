enum BrowserPagePresentation: String, CaseIterable, Decodable, Equatable, Sendable {
    case noSelection
    case startPage
    case nativeContent
    case livePage
    case navigationFailure
    case processFailure
    case unloaded
    case automaticRestore
}

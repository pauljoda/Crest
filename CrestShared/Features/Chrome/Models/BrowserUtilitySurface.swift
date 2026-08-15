enum BrowserUtilitySurface: CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case archive
    case history
    case downloads

    var id: Self { self }
}

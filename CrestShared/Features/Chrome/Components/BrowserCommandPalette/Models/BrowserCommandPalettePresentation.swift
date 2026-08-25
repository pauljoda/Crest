import CoreGraphics

enum BrowserCommandPalettePresentation: Equatable, Sendable {
    case overlay
    case embedded
}

struct BrowserCommandPalettePresentationIdentity: Hashable {
    let mode: BrowserCommandPaletteMode?
    let focusRequest: Int?
    let source: BrowserTabRuntimeAssignment?
    let searchProvider: BrowserSearchProvider?
    let searchSuggestionsEnabled: Bool?

    init(
        mode: BrowserCommandPaletteMode,
        space: BrowserSpace?,
        source: BrowserTabRuntimeAssignment?
    ) {
        self.mode = mode
        focusRequest = nil
        self.source = source
        searchProvider = space?.browsingPreferences.searchProvider
        searchSuggestionsEnabled =
            space?.browsingPreferences.searchSuggestionsEnabled
    }

    init(
        focusRequest: Int? = nil,
        space: BrowserSpace?,
        source: BrowserTabRuntimeAssignment?
    ) {
        mode = nil
        self.focusRequest = focusRequest
        self.source = source
        searchProvider = space?.browsingPreferences.searchProvider
        searchSuggestionsEnabled =
            space?.browsingPreferences.searchSuggestionsEnabled
    }
}

struct BrowserCommandPaletteOverlayTransitionState: Equatable, Sendable {
    let opacity: Double
    let scale: CGFloat

    static let hidden = Self(opacity: 0, scale: 1)
    static let presented = Self(opacity: 1, scale: 1)
}

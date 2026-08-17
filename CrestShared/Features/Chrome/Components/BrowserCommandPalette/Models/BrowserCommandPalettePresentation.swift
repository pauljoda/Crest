import CoreGraphics

enum BrowserCommandPalettePresentation: Equatable, Sendable {
    case overlay
    case embedded
}

struct BrowserCommandPalettePresentationIdentity: Hashable {
    let mode: BrowserCommandPaletteMode?
    let focusRequest: Int?
    let source: BrowserTabRuntimeAssignment?
    let otherSpaces: [BrowserSpaceRuntimeAssignment]

    init(
        mode: BrowserCommandPaletteMode,
        source: BrowserTabRuntimeAssignment?,
        otherSpaces: [BrowserSpace] = []
    ) {
        self.mode = mode
        focusRequest = nil
        self.source = source
        self.otherSpaces = otherSpaces.map(BrowserSpaceRuntimeAssignment.init)
    }

    init(
        focusRequest: Int? = nil,
        source: BrowserTabRuntimeAssignment?,
        otherSpaces: [BrowserSpace] = []
    ) {
        mode = nil
        self.focusRequest = focusRequest
        self.source = source
        self.otherSpaces = otherSpaces.map(BrowserSpaceRuntimeAssignment.init)
    }
}

struct BrowserCommandPaletteOverlayTransitionState: Equatable, Sendable {
    let opacity: Double
    let scale: CGFloat

    static let hidden = Self(opacity: 0, scale: 1)
    static let presented = Self(opacity: 1, scale: 1)
}

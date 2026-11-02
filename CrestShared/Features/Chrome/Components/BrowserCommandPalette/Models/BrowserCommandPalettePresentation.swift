import SwiftUI

/// Where a palette appears and how it fits there: centered over its window,
/// in place on the Start Page, or grown out of an address field, whose text
/// stays the palette's input line while the results drop below the field or
/// rise above it.
struct BrowserCommandPalettePresentation: Equatable, Sendable {
    // MARK: - Types

    /// The palette's input line: a prominent one of its own, or one the size
    /// of the address field it grows out of.
    struct Input: Equatable, Sendable {
        #if os(macOS)
            typealias PlatformTextStyle = NSFont.TextStyle
        #else
            typealias PlatformTextStyle = UIFont.TextStyle
        #endif

        static let prominent = Input(
            textStyle: .title2, platformTextStyle: .title2, fieldHeight: 32,
            minimumHeight: BrowserCommandPaletteMetrics.searchFieldMinimumHeight,
            horizontalPadding: BrowserCommandPaletteMetrics.searchFieldHorizontalPadding, showsSearchGlyph: true)
        #if os(macOS)
            static let inline = Input(
                textStyle: .body, platformTextStyle: .body, fieldHeight: 22,
                minimumHeight: BrowserChromeLayout.addressHeight, horizontalPadding: 12, showsSearchGlyph: false)
        #else
            /// The compact address bar's size: a 48-point capsule.
            static let inline = Input(
                textStyle: .body, platformTextStyle: .body, fieldHeight: 24, minimumHeight: 48,
                horizontalPadding: 14, showsSearchGlyph: false)
        #endif

        let textStyle: Font.TextStyle
        let platformTextStyle: PlatformTextStyle
        /// The editor's height at the default text size, which scales with
        /// `textStyle`.
        let fieldHeight: CGFloat
        let minimumHeight: CGFloat
        let horizontalPadding: CGFloat
        let showsSearchGlyph: Bool
    }

    // MARK: - Static Variables

    /// Centered over the window on a scrim, keeping one height whatever its
    /// results; its close button, Escape and a click outside close it.
    static let overlay = BrowserCommandPalettePresentation(
        input: .prominent, centersOverWindow: true, growsFromField: false, listsUpward: false, keepsHeight: true,
        closesOnExit: true, showsCloseButton: true, minimumWidth: 0, fieldIdentifier: "command-palette-field")

    /// In place on the Start Page, where it stays.
    static let embedded = BrowserCommandPalettePresentation(
        input: .prominent, centersOverWindow: false, growsFromField: false, listsUpward: false, keepsHeight: false,
        closesOnExit: false, showsCloseButton: false, minimumWidth: 0,
        fieldIdentifier: "start-page-command-palette-field")

    /// Grown out of an address field at the top of a window, its results
    /// dropping below the field, and wider than a narrow field so they stay
    /// readable. Escape and a click outside close it.
    static let dropping = BrowserCommandPalettePresentation(
        input: .inline, centersOverWindow: false, growsFromField: true, listsUpward: false, keepsHeight: false,
        closesOnExit: true, showsCloseButton: false, minimumWidth: 440,
        fieldIdentifier: "address-command-palette-field")

    /// Grown out of an address bar at the bottom of the screen, its results
    /// rising above the bar with the best match nearest it. It spans the
    /// screen over the controls beside the bar, so the results stay readable.
    static let rising = BrowserCommandPalettePresentation(
        input: .inline, centersOverWindow: false, growsFromField: true, listsUpward: true, keepsHeight: false,
        closesOnExit: true, showsCloseButton: false, minimumWidth: .infinity,
        fieldIdentifier: "address-command-palette-field")

    // MARK: - Variables

    let input: Input
    /// Whether the palette sits centered over its window on a scrim.
    let centersOverWindow: Bool
    /// Whether the palette grows out of an address field, its input line over
    /// the field.
    let growsFromField: Bool
    /// Whether the results sit above the input line, the first nearest it.
    let listsUpward: Bool
    /// Whether the palette keeps one height while its results change.
    let keepsHeight: Bool
    /// Whether Escape closes the palette.
    let closesOnExit: Bool
    let showsCloseButton: Bool
    /// How wide a palette grown out of a field is at least, however narrow
    /// the field.
    let minimumWidth: CGFloat
    let fieldIdentifier: String

    /// The palette's corner radius: the address field's where it grows out of
    /// one, which on Mac follows Look and Feel and on iPhone and iPad is a
    /// capsule's, else the card's own.
    @MainActor var cornerRadius: CGFloat {
        guard growsFromField else { return BrowserCommandPaletteMetrics.cardCornerRadius }
        #if os(macOS)
            return BrowserDeviceAppearanceStore.shared.sidebarCornerRadius
        #else
            return input.minimumHeight / 2
        #endif
    }

    // MARK: - Initializers

    private init(
        input: Input, centersOverWindow: Bool, growsFromField: Bool, listsUpward: Bool, keepsHeight: Bool,
        closesOnExit: Bool, showsCloseButton: Bool, minimumWidth: CGFloat, fieldIdentifier: String
    ) {
        self.input = input
        self.centersOverWindow = centersOverWindow
        self.growsFromField = growsFromField
        self.listsUpward = listsUpward
        self.keepsHeight = keepsHeight
        self.closesOnExit = closesOnExit
        self.showsCloseButton = showsCloseButton
        self.minimumWidth = minimumWidth
        self.fieldIdentifier = fieldIdentifier
    }
}

/// What a palette is opened for. A palette opened again for other values
/// starts over, so a stale query never survives into another tab or Space.
struct BrowserCommandPalettePresentationIdentity: Hashable {
    // MARK: - Variables

    let mode: BrowserCommandPaletteMode?
    let focusRequest: Int?
    let source: BrowserTabRuntimeAssignment?
    let spaceAssignment: BrowserSpaceRuntimeAssignment?

    // MARK: - Initializers

    @MainActor
    init(mode: BrowserCommandPaletteMode, space: SpaceModel?, source: BrowserTabRuntimeAssignment?) {
        self.mode = mode
        focusRequest = nil
        self.source = source
        spaceAssignment = space.map { BrowserSpaceRuntimeAssignment(spaceID: $0.id, profileID: $0.profileID) }
    }

    @MainActor
    init(focusRequest: Int? = nil, space: SpaceModel?, source: BrowserTabRuntimeAssignment?) {
        mode = nil
        self.focusRequest = focusRequest
        self.source = source
        spaceAssignment = space.map { BrowserSpaceRuntimeAssignment(spaceID: $0.id, profileID: $0.profileID) }
    }
}

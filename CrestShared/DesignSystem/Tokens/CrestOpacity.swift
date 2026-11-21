/// Shared opacity roles for custom interaction and accessibility states.
enum CrestOpacity {
    static let dropIndicator = 0.72
    static let hover = 0.08
    /// The wash of ink under a selected row or control.
    static let selection = 0.13
    /// The edge a selected row or control wears.
    static let selectedBorder = 0.10
    static let interactionSelectionShadow = 0.08
    /// The ink shadow a selection on Crest's paper casts on the layer under
    /// it.
    static let paperShadow = 0.16
    /// How opaque the sheet of paper under a selected tab is, unless the
    /// person chooses otherwise: enough to read as paper, with what lies
    /// under it, such as a pin's site color, still showing through.
    static let selectedTabPaper = 0.8
    /// How strongly a selected pin's color is washed over the paper laid on
    /// it, on top of what shows through the paper, so the color still comes
    /// through solid paper.
    static let selectedPinTint = 0.3
    /// How far a selected tab on the device's material lifts dark glass
    /// toward white, so it stands off a dark sidebar as light glass does off
    /// any.
    static let darkSelectionLift = 0.10
    /// The edge a selected tab's dark glass wears over a dark sidebar.
    static let darkSelectionBorder = 0.18
    static let chromeSurface = 0.055
    static let border = 0.12
    /// A disabled glyph, drawn in the secondary label color at this
    /// opacity so it stays visible against both page and sidebar glass.
    static let disabledGlyph = 0.5
    /// A disabled control, such as a filled button, faded as a whole.
    static let disabledControl = 0.42
    /// Chrome that belongs to a part of the window without focus but stays
    /// usable, such as the bar of a split card another card has focus over.
    static let unfocusedChrome = 0.5
    static let controlShadow = 0.16
    /// A status drawn across a sidebar row, under its title.
    static let statusSurface = 0.35
    /// A status drawn across a pinned tile, which is small and sits on its
    /// own plate.
    static let prominentStatusSurface = 0.6
    /// A status colour washed under a row or tag, beneath its own text.
    static let statusFill = 0.18
}

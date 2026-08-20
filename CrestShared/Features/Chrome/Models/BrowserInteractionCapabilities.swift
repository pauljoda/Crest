/// What the hosting environment can do — never which device it is.
///
/// Constructed once per shell instance and handed down through the chrome, so
/// a row asks what its environment supports rather than which target compiled
/// it. The bits are independent rather than a device taxonomy: an iPad with a
/// trackpad attached is touch *and* hover at the same time, and reading the
/// two together is the only way that shell gets both a reachable hit target
/// and a hover state.
struct BrowserInteractionCapabilities: Equatable, Sendable {
    /// Whether a pointer can rest over a row without committing to it. Only
    /// affordances that a resting pointer can reveal may depend on this.
    var supportsHover = true

    /// Whether fingers are a first-class input. Sizing follows the least
    /// precise input the shell accepts, so this stays on for a touch shell
    /// even while a trackpad is attached.
    var supportsTouch = false

    /// Whether a drag draws its insertion line on the row it would land
    /// against. Where this is off, the section's own zone carries the whole
    /// drop feedback and individual rows stay quiet.
    var showsRowDropIndicators = false

    /// Whether a reorder keeps landing slots open at a section's ends. A
    /// finger cannot aim at the seam between two rows that touch, so those
    /// places are reserved rather than inferred from the gap.
    var reservesReorderSectionZones = false

    /// Whether selecting a tab zooms into the page with the system's own
    /// navigation transition. Per shell rather than per platform: a shell that
    /// never pushes a page has nothing to zoom into.
    var usesNativeNavigationTransition = false

    /// Whether a surface in this shell grows out of a sidebar row through a
    /// matched-geometry pairing — the windowed shell's start page, whose command
    /// palette rises out of the row that opened it and registers the source end
    /// of the pairing.
    ///
    /// Not the same question as the native zoom, and not its negation. A shell
    /// can have neither: the compact shell pairs its pushed page with the row
    /// through the system transition, and its other placements keep the page on
    /// screen the whole time and pair nothing at all. Where nothing pairs, the
    /// row must claim no anchor — an anchor is a presentation transform over the
    /// very view the system drag interaction lifts, and one with no partner can
    /// only cost.
    var pairsRowWithPromotedSurface = true
}

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
}

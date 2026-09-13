import SwiftUI

/// Independent interaction features supplied by the shell. Touch and hover may coexist.
struct BrowserInteractionCapabilities: Equatable, Sendable {
    /// Enables affordances revealed by a resting pointer.
    var supportsHover = true

    /// Keeps touch-sized targets available, including when a pointer is attached.
    var supportsTouch = false

    /// Shows insertion feedback on individual rows instead of section zones alone.
    var showsRowDropIndicators = false

    /// Reserves drop targets at section boundaries for imprecise input.
    var reservesReorderSectionZones = false

    /// Uses the system navigation transition when a row pushes a page.
    var usesNativeNavigationTransition = false

    /// Registers a matched-geometry anchor only when a promoted surface has a matching destination.
    var pairsRowWithPromotedSurface = true

    /// Allows drag, drop, and organization menus. Appearance previews disable this.
    var supportsOrganization = true
}

extension EnvironmentValues {
    @Entry var browserInteractionCapabilities = BrowserInteractionCapabilities()
}

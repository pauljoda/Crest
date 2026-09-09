enum BrowserSpacePagerPolicy {

    /// Whether something in flight owns the horizontal axis.
    ///
    /// Three sources, because a sidebar item can be picked up three ways and any
    /// of them is spoiled by the strip paging underneath it. The sidebar lift is
    /// named first and separately: it is the only one a touch shell ever raises,
    /// and reading the two pointer drag states alone left the pager live under
    /// every finger drag.
    static func isInteractionLocked(
        hasSidebarLift: Bool,
        hasTabDrag: Bool,
        hasFolderDrag: Bool
    ) -> Bool {
        hasSidebarLift || hasTabDrag || hasFolderDrag
    }

}

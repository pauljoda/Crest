enum MobileBrowserSpaceSwitchPolicy {
    static func destinationAfterLeavingLockedSpace(
        in presentation: MobileBrowserPresentation
    ) -> MobileBrowserSpaceSwitchDestination {
        presentation == .compact ? .tabViewer : .selectedPage
    }
}

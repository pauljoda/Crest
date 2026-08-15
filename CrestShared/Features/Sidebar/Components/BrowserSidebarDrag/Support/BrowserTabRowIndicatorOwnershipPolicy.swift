enum BrowserTabRowIndicatorOwnershipPolicy {
    static func showsAfterRowIndicator(
        hasVisibleFollowingRow: Bool
    ) -> Bool {
        !hasVisibleFollowingRow
    }

    static func showsSectionEndIndicator(hasVisibleRows: Bool) -> Bool {
        !hasVisibleRows
    }
}

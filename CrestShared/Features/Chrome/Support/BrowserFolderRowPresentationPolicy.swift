enum BrowserFolderRowPresentationPolicy {
    static let showsSeparateChevron = false
    static let usesEntireRowForDisclosure = true

    static func systemImage(isExpanded: Bool) -> String {
        isExpanded ? "folder.fill" : "folder"
    }

    /// Whether a collapsed folder's header lights up the way a row does, given
    /// the lift that would land inside it on release.
    ///
    /// A tab filed into a folder becomes one of the folder's rows, so a row's
    /// own selection treatment is the honest preview of what release does.
    /// `nil` — nothing lifted, or the lift is aimed somewhere else — draws
    /// nothing, which is why the whole rule reads from one value.
    static func showsDropHighlight(
        for lift: BrowserSidebarReorderItem?
    ) -> Bool {
        if case .some(.tab) = lift { return true }
        return false
    }

    /// Whether the header wears an outline around the whole row instead.
    ///
    /// A folder filed inside another changes the structure rather than the
    /// contents, and an outline says "inside this one" where a row highlight
    /// would only say "one of these". A split group can never appear here: it
    /// moves as one block and refuses folder zones outright.
    static func showsNestOutline(
        for lift: BrowserSidebarReorderItem?
    ) -> Bool {
        if case .some(.folder) = lift { return true }
        return false
    }
}

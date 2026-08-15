enum BrowserFolderRowPresentationPolicy {
    static let showsSeparateChevron = false
    static let usesEntireRowForDisclosure = true

    static func systemImage(isExpanded: Bool) -> String {
        isExpanded ? "folder.fill" : "folder"
    }

    static func showsDropHighlight(
        isTargeted: Bool,
        isTabDragging: Bool
    ) -> Bool {
        isTargeted && isTabDragging
    }
}

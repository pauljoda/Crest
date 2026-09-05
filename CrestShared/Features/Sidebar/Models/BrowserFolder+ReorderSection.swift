extension BrowserFolder {
    var reorderSection: BrowserSidebarReorderSection {
        .tabs(placement: location.tabPlacement, folderID: parentID)
    }
}

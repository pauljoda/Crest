struct BrowserFolderDropLocation: Equatable, Sendable {
    let parentID: FolderID?
    let beforeSiblingID: FolderID?
}

struct BrowserTabDropLocation: Equatable, Sendable {
    let placement: TabPlacement
    let folderID: FolderID?
    let beforeTabID: TabID?
    var destinationAssignment: BrowserSpaceRuntimeAssignment? = nil
}

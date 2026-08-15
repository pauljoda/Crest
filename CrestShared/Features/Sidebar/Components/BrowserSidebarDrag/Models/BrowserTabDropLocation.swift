struct BrowserTabDropLocation: Equatable, Sendable {
    let placement: TabPlacement
    let folderID: FolderID?
    let beforeTabID: TabID?
    var destinationAssignment: BrowserSpaceRuntimeAssignment? = nil
}

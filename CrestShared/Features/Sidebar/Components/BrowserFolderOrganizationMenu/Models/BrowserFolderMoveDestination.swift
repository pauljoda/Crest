struct BrowserFolderMoveDestination: Identifiable {
    let node: BrowserFolderNode
    let path: String

    var id: FolderID { node.id }
}

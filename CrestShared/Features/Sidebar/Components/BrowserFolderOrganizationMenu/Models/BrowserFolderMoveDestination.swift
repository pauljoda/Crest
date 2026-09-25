struct BrowserFolderMoveDestination: Identifiable {
    let folder: FolderStateModel
    let path: String

    var id: FolderID { folder.id }
}

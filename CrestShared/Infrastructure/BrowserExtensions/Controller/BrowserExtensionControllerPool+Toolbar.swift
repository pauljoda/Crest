extension BrowserExtensionControllerPool {
    func setPinned(
        _ pinned: Bool,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        guard
            toolbarController.setPinned(
                pinned,
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return
        }
        recordActionMutations()
    }
}

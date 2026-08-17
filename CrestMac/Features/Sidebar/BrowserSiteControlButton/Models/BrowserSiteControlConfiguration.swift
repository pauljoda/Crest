struct BrowserSiteControlConfiguration {
    let page: BrowserPage
    let space: BrowserSpace
    let selectedTabID: TabID?
    let extensionControllerPool: BrowserExtensionControllerPool
    let permissionCenter: BrowserSitePermissionCenter
    let manageExtensions: () -> Void
    let presentationChanged: (Bool) -> Void
    let contextMenuPresentationChanged: (Bool) -> Void
}

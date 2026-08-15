struct BrowserSiteControlConfiguration {
    let page: BrowserPage
    let space: BrowserSpace
    let selectedTabID: TabID?
    let extensionControllerPool: BrowserExtensionControllerPool
    let permissionCenter: BrowserSitePermissionCenter
    let manageExtensions: () -> Void
}

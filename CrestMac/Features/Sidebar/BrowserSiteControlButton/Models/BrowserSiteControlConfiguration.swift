struct BrowserSiteControlConfiguration {
    let page: BrowserPage
    let space: BrowserSpace
    let selectedTabID: TabID?
    let permissionCenter: BrowserSitePermissionCenter
    let presentationChanged: (Bool) -> Void
    let contextMenuPresentationChanged: (Bool) -> Void
}

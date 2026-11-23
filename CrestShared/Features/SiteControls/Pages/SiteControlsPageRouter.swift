import SwiftUI

/// The one place a page of Site Controls becomes its rows. The Extensions
/// page comes from the shell, which composes the engine that has them.
struct SiteControlsPageRouter<ExtensionsPage: View>: View {
    let model: SiteControlsModel
    let page: SiteControlsPage
    let extensionsPage: () -> ExtensionsPage

    @ViewBuilder
    var body: some View {
        switch page.kind {
        case .connection: SiteControlsConnectionPage(model: model)
        case .blocking: SiteControlsBlockingPage(model: model)
        case .permissions: SiteControlsPermissionsPage(model: model)
        case .extensions: extensionsPage()
        case .siteData: SiteControlsSiteDataPage(model: model)
        case .downloads: SiteControlsDownloadsPage(model: model)
        case .translate: SiteControlsTranslatePage(model: model)
        case .actions: SiteControlsActionsPage(model: model)
        case .qrCode: SiteControlsQRCodePage(model: model)
        }
    }

    /// What stays above the page's scrolling rows: the editor's four slots
    /// while the actions page edits them.
    @ViewBuilder
    var pinned: some View {
        if page.kind == .actions, model.isEditingActions {
            SiteControlsActionSlots(model: model)
        }
    }
}

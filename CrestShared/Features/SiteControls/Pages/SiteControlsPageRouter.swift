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
        case .siteSettings:
            SiteControlsPageSection {
                SiteControlsRowLabel(title: Text("Automatic Picture in Picture"), symbol: "pip") {
                    Menu {
                        Button("Use App Settings", systemImage: "gearshape") {
                            model.setDecision(.ask, for: .automaticPictureInPicture)
                        }
                        Button("Block", systemImage: "nosign") {
                            model.setDecision(.denyPersistently, for: .automaticPictureInPicture)
                        }
                        .crestMenuActionLabelStyle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(
                                model.blocksAutomaticPictureInPicture
                                    ? LocalizedStringKey("Blocked") : LocalizedStringKey("Use App Settings")
                            )
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel("Automatic Picture in Picture")
                    .accessibilityValue(
                        model.blocksAutomaticPictureInPicture ? Text("Blocked") : Text("Use App Settings")
                    )
                    .accessibilityIdentifier("site-automatic-picture-in-picture")
                }
            }
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

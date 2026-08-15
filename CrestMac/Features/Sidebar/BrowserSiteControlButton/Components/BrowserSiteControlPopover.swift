import AppKit
import SwiftUI

struct BrowserSiteControlPopover: View {
    let configuration: BrowserSiteControlConfiguration
    let dismiss: () -> Void
    var actionPresentationOverride: [BrowserExtensionActionPresentation]? = nil

    @State private var isPermissionsExpanded =
        BrowserSitePermissionDisclosurePolicy.defaultIsExpanded

    var body: some View {
        ScrollView {
            BrowserSiteControlContent(
                configuration: configuration,
                actions: presentedActions,
                permissionsExpansion: $isPermissionsExpanded,
                dismiss: dismiss,
                manageExtensions: manageExtensions,
                performExtensionAction: perform,
                togglePinned: togglePinned,
                reviewCertificate: reviewCertificate,
                presentExtensionMenu: presentMenu
            )
        }
        .id(isPermissionsExpanded)
        .frame(
            width: BrowserSiteControlLayoutPolicy.width,
            height: BrowserSiteControlLayoutPolicy.height(
                permissionsExpanded: isPermissionsExpanded
            )
        )
        .frame(maxHeight: BrowserSiteControlLayoutPolicy.maximumHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Site Controls")
        .accessibilityIdentifier("browser-site-controls-popover")
    }

    private var toolbarActions: [BrowserExtensionToolbarAction] {
        configuration.extensionControllerPool.toolbarActions(
            in: configuration.space.id,
            tabID: configuration.selectedTabID
        )
    }

    private var presentedActions: [BrowserExtensionActionPresentation] {
        actionPresentationOverride
            ?? toolbarActions.map(BrowserExtensionActionPresentation.init(action:))
    }

    private func perform(
        _ presentation: BrowserExtensionActionPresentation,
        popupAnchor: BrowserExtensionPopupAnchor?
    ) {
        guard
            let action = toolbarActions.first(where: {
                $0.id == presentation.id
            })
        else { return }
        dismiss()
        configuration.extensionControllerPool.perform(
            action,
            popupAnchor: popupAnchor?
                .replacingSourceWindow(configuration.page.webView.window)
                ?? BrowserExtensionPopupAnchor(
                    screenPoint: NSEvent.mouseLocation,
                    sourceWindow: configuration.page.webView.window
                )
        )
    }

    private func presentMenu(
        _ presentation: BrowserExtensionActionPresentation,
        anchor: BrowserExtensionPopupAnchor?
    ) {
        guard
            let action = toolbarActions.first(where: {
                $0.id == presentation.id
            })
        else { return }
        let window = configuration.page.webView.window
        // The popover owns the click that opened this menu, so it has to go
        // before the menu takes over event tracking. Re-anchor to the browser
        // window, which is still there once the popover is gone.
        dismiss()
        Task { @MainActor in
            await Task.yield()
            BrowserExtensionContextMenu.present(
                for: action,
                pool: configuration.extensionControllerPool,
                spaceID: configuration.space.id,
                anchor: anchor?.replacingSourceWindow(window)
                    ?? BrowserExtensionPopupAnchor(
                        screenPoint: NSEvent.mouseLocation,
                        sourceWindow: window
                    ),
                manageExtensions: configuration.manageExtensions
            )
        }
    }

    private func togglePinned(
        _ presentation: BrowserExtensionActionPresentation
    ) {
        guard
            let action = toolbarActions.first(where: {
                $0.id == presentation.id
            })
        else { return }
        configuration.extensionControllerPool.setPinned(
            !action.isPinned,
            extensionID: action.id,
            in: configuration.space.id
        )
    }

    private func manageExtensions() {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            configuration.manageExtensions()
        }
    }

    private func reviewCertificate() {
        guard let trust = configuration.page.webView.serverTrust else { return }
        let window = configuration.page.webView.window
        dismiss()
        Task { @MainActor in
            await Task.yield()
            BrowserSiteCertificatePresenter.present(trust: trust, for: window)
        }
    }
}

#Preview("Site Control Popover") {
    let preview = BrowserSidebarExtensionPreviewFixture.makeContext()
    BrowserSiteControlPopover(
        configuration: preview.configuration,
        dismiss: {},
        actionPresentationOverride: BrowserSidebarExtensionPreviewFixture.actions
    )
}

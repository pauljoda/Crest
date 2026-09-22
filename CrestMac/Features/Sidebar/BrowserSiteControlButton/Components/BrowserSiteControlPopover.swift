import AppKit
import SwiftUI

struct BrowserSiteControlPopover: View {
    let configuration: BrowserSiteControlConfiguration
    let dismiss: () -> Void

    @State private var isPermissionsExpanded =
        BrowserSitePermissionDisclosurePolicy.defaultIsExpanded

    var body: some View {
        ScrollView {
            BrowserSiteControlContent(
                configuration: configuration,
                permissionsExpansion: $isPermissionsExpanded,
                dismiss: dismiss,
                reviewCertificate: reviewCertificate
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
        .onAppear {
            if configuration.page.blockedPopupNotice != nil {
                isPermissionsExpanded = true
            }
        }
    }

    private func reviewCertificate() {
        guard let review = configuration.page.certificateReviewAction() else { return }
        dismiss()
        Task { @MainActor in
            await Task.yield()
            review()
        }
    }
}

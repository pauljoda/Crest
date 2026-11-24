import SwiftUI

/// The address field in a page card's bar: the card's own page, its lock,
/// address, Copy URL, reload and Site Controls, dressed as the sidebar's field
/// is. A click anywhere on it opens the window's command palette over it,
/// which is where the address is edited.
struct BrowserPageCardAddressField: View {
    // MARK: - Static Variables

    /// The sidebar's own field, so the two match in height, corners and
    /// spacing, and follow the same corner setting.
    private static let metrics = BrowserSidebarAddressFieldMetrics.pointer

    // MARK: - Variables

    let page: BrowserPage?
    let tab: TabStateModel?
    let space: SpaceModel?
    let pages: BrowserPagePool
    /// Whether the window's palette lies over this field, which then hides
    /// under it until the palette closes.
    let isUnderPalette: Bool
    /// Where the field reports its frame for the palette to drop out of.
    let fieldFrames: BrowserPageBarFieldFrames
    let activate: () -> Void

    /// The field's width, which decides whether Copy URL fits beside Site
    /// Controls.
    @State private var fieldWidth: CGFloat = .infinity
    /// Whether the pointer is over the field, which brings Copy URL back in a
    /// field too narrow to keep it.
    @State private var isHovering = false
    /// This field's stamp on the frame it reports, so a field for the same
    /// tab arriving before this one leaves keeps its entry.
    @State private var frameOwner = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.metrics.contentSpacing) {
            leadingControl
            BrowserAddressContent(
                text: .constant(address),
                isEditing: .constant(false),
                activate: activate,
                editorAccessibilityLabel: "Page address",
                editorAccessibilityIdentifier: "page-card-address",
                summaryAccessibilityIdentifier: "page-card-address-display",
                display: BrowserDeviceAppearanceStore.shared.address.display,
                submit: {}
            )
            HStack(spacing: Self.metrics.accessorySpacing) {
                if let page, page.credentialHeldSaveCandidate != nil {
                    BrowserAddressSavePasswordButton(page: page)
                }
                if let copyURLPage {
                    BrowserAddressCopyURLButton(page: copyURLPage)
                }
                if let page {
                    BrowserReloadControl(
                        isLoading: page.live.isLoading,
                        isDeveloperMode: page.isDeveloperModeEnabled,
                        reloadOrStop: { page.performReload(.standard) },
                        reload: { page.performReload(.standard) },
                        reloadFromOrigin: { page.performReload(.fromOrigin) },
                        clearCookiesAndReload: { await page.clearSiteData(.siteData) },
                        reloadControlSize: BrowserPageBarMetrics.reloadControlSize,
                        menuControlSize: BrowserPageBarMetrics.reloadMenuControlSize
                    )
                }
                if let siteControl {
                    BrowserSiteControlButton(configuration: siteControl)
                }
            }
        }
        .browserAddressFieldSurface(
            metrics: Self.metrics,
            progress: page?.estimatedProgress ?? 0,
            isLoading: page?.live.isLoading == true,
            isEditing: false,
            branding: space?.settings.look,
            activate: activate
        )
        // Fades as the palette's surface grows out of it, and back as the
        // palette shrinks into it, at the sidebar field's pace.
        .animation(isUnderPalette ? BrowserCommandSurfaceMorph.leadingFade : BrowserCommandSurfaceMorph.trailingFade) {
            $0.opacity(isUnderPalette ? 0 : 1)
        }
        .allowsHitTesting(!isUnderPalette)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { fieldWidth = $0 }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            if let tabID = tab?.id { fieldFrames.register(frame, for: tabID, owner: frameOwner) }
        }
        .onDisappear {
            if let tabID = tab?.id { fieldFrames.removeFrame(for: tabID, owner: frameOwner) }
        }
        .onHover { hovering in
            withAnimation(CrestMotion.controlState.unlessReducingMotion(reduceMotion)) { isHovering = hovering }
        }
    }

    /// The certificate button for a live site, else the lock or the search
    /// glyph in its place.
    @ViewBuilder
    private var leadingControl: some View {
        if let page, page.live.displayURL != nil {
            BrowserAddressSecurityButton(page: page, isSecure: isSecure)
        } else {
            BrowserSidebarAddressPlaceholderGlyph(isSecure: isSecure, metrics: Self.metrics)
        }
    }

    /// The page's address, or the tab's while it has no page.
    private var address: String {
        page?.live.displayURL?.absoluteString ?? tab?.url ?? ""
    }

    private var isSecure: Bool {
        PageSecurity.isSecure(page: page?.live, storedAddress: tab?.url)
    }

    /// The page the Copy URL button copies, while the person turned the
    /// button on, the field has room for it or the pointer is over it, and
    /// the page has an address to copy.
    private var copyURLPage: BrowserPage? {
        guard BrowserDeviceAppearanceStore.shared.address.showsCopyURLButton,
            isHovering || fieldWidth >= BrowserSidebarAddressFieldMetrics.copyURLButtonMinimumWidth,
            let page, page.live.documentURL != nil
        else { return nil }
        return page
    }

    /// The page's Site Controls: its site settings, permission requests and
    /// extensions. A request on this card's page opens them here, on this
    /// card, whether or not it has focus.
    private var siteControl: BrowserSiteControlConfiguration? {
        guard let page, page.live.displayURL != nil, let space else { return nil }
        return BrowserSiteControlConfiguration(
            page: page, space: space, selectedTabID: tab?.id,
            presentationChanged: { _ in }, contextMenuPresentationChanged: { _ in })
    }
}

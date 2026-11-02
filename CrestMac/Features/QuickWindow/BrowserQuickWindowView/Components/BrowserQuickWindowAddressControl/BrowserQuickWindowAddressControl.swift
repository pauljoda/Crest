import SwiftUI

struct BrowserQuickWindowAddressControl: View {
    // MARK: - Static Variables

    /// The whole field, Space chip included, which the address centers its
    /// text in.
    private static let field = NamedCoordinateSpace.named("crest.quick-window.address-field")

    // MARK: - Variables

    let model: BrowserQuickWindowModel
    @Binding var addressText: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int

    @Environment(\.scenePhase) private var scenePhase
    @Environment(BrowserChromeState.self) private var chrome: BrowserChromeState?

    var body: some View {
        HStack(spacing: 7) {
            BrowserQuickWindowSourceSpaceIndicator(
                space: model.spaceModel?.identity,
                spaces: model.availableSpaceModels.map(\.identity),
                selectSpace: model.selectSpace
            )
            Divider().frame(height: 16)
            BrowserQuickWindowAddressSecurityIcon(
                isSecure: model.page?.live.security.isSecure == true
            )
            BrowserAddressContent(
                text: $addressText,
                isEditing: $isAddressEditing,
                focusRequest: addressFocusRequest,
                activate: openPalette,
                editorAccessibilityLabel: "Quick Window address",
                editorAccessibilityIdentifier: "quick-window-address",
                summaryAccessibilityIdentifier: "quick-window-address-display",
                prompt: "Search or enter a website",
                centeringField: Self.field,
                submit: openAddress
            )
            .padding(.vertical, BrowserQuickWindowLayout.addressVerticalPadding)
            BrowserQuickWindowAddressTrailingControl(
                page: model.page,
                addressText: $addressText,
                isAddressEditing: isAddressEditing,
                reloadOrStop: reloadOrStop
            )
            if let siteControl {
                BrowserSiteControlButton(configuration: siteControl)
            }
        }
        .browserAddressFieldSurface(
            leadingPadding: BrowserQuickWindowLayout.sourceChipLeadingInset,
            progress: model.page?.estimatedProgress ?? 0,
            isLoading: model.page?.live.isLoading == true,
            isEditing: isAddressEditing,
            isGlass: true
        )
        .coordinateSpace(Self.field)
        .anchorPreference(key: BrowserQuickWindowCommandPaletteLayer.FieldAnchor.self, value: .bounds) { $0 }
        // The palette grows out of the field and its input line takes the
        // field's place until it closes.
        .opacity(isPaletteShown ? 0 : 1)
        .allowsHitTesting(!isPaletteShown)
        .accessibilityHidden(isPaletteShown)
        .frame(
            minWidth: BrowserQuickWindowLayout.addressMinimumWidth,
            maxWidth: .infinity
        )
    }

    /// The page's Site Controls, as a browser window's address field offers
    /// them: its site settings, permission requests and extensions.
    private var siteControl: BrowserSiteControlConfiguration? {
        guard let page = model.page, page.live.displayURL != nil, let space = model.spaceModel,
            let pages = model.pages
        else { return nil }
        return BrowserSiteControlConfiguration(
            page: page, space: space, selectedTabID: nil, permissionCenter: pages.permissionCenter,
            presentationChanged: { _ in }, contextMenuPresentationChanged: { _ in })
    }

    private var isPaletteShown: Bool { chrome?.commandPaletteMode != nil }

    /// Opens the palette over the field, starting at the page's address;
    /// without one the field edits in place.
    private var openPalette: (() -> Void)? {
        guard let chrome else { return nil }
        return { [model] in chrome.openLocation(model.address) }
    }

    // MARK: - Actions - Page

    private func openAddress() {
        guard let space = model.spaceModel,
            let resolved = try? model.browser.core.query(
                ResolveAddress(workspaceID: model.browser.family.workspaceID, spaceID: space.id, input: addressText)),
            let url = resolved.url.flatMap(URL.init(string:))
        else { return }
        addressText = url.absoluteString
        model.open(url, isActive: scenePhase == .active)
    }

    private func reloadOrStop() {
        model.recordUserActivity()
        model.page?.performReload(.standard)
    }
}

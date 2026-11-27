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
    let commandSurfaceNamespace: Namespace.ID
    let commandPaletteHandoff: BrowserCommandPaletteHandoff

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BrowserChromeState.self) private var chrome: BrowserChromeState?
    @Environment(\.browserMacWindows) private var windows

    var body: some View {
        HStack(spacing: 7) {
            BrowserQuickWindowSourceSpaceIndicator(
                space: model.spaceModel?.identity,
                spaces: model.availableSpaceModels.map(\.identity),
                selectSpace: model.selectSpace
            )
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
                display: BrowserDeviceAppearanceStore.shared.address.display,
                submit: openAddress
            )
            .padding(.vertical, BrowserQuickWindowLayout.addressVerticalPadding)
            HStack(spacing: BrowserQuickWindowLayout.trailingControlSpacing) {
                BrowserQuickWindowAddressTrailingControl(
                    page: model.page,
                    addressText: $addressText,
                    isAddressEditing: isAddressEditing,
                    reloadOrStop: reloadOrStop
                )
                if let siteControl {
                    BrowserSiteControlButton(configuration: siteControl)
                        .environment(\.browserWindowCommands, windowCommands)
                }
            }
        }
        .browserAddressFieldSurface(
            leadingPadding: BrowserQuickWindowLayout.sourceChipLeadingInset,
            progress: model.page?.estimatedProgress ?? 0,
            isLoading: model.page?.live.isLoading == true,
            isEditing: isAddressEditing,
            activate: openFromSurface
        )
        .coordinateSpace(Self.field)
        .anchorPreference(key: BrowserQuickWindowCommandPaletteLayer.FieldAnchor.self, value: .bounds) { $0 }
        // The palette rises over the field and its input line takes the
        // field's place until it closes.
        .animation(commandPaletteHandoff.fieldAnimation.unlessReducingMotion(reduceMotion)) {
            $0.opacity(isPaletteShown ? 0 : 1)
        }
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
        guard let page = model.page, page.live.displayURL != nil, let space = model.spaceModel, model.pages != nil
        else { return nil }
        return BrowserSiteControlConfiguration(
            page: page, space: space, selectedTabID: nil,
            presentationChanged: { _ in }, contextMenuPresentationChanged: { _ in })
    }

    /// The page commands as they run in this Quick Window, on its page, which
    /// its Site Controls run.
    private var windowCommands: BrowserWindowCommands? {
        guard let chrome, let pages = model.pages, let page = model.page else { return nil }
        return BrowserWindowCommands(
            actions: BrowserCommandActions(
                browser: model.browser, pages: pages, chrome: chrome, windows: windows,
                targetWindowID: model.presentedRequest.targetWindowID, quickWindowPage: page),
            shortcuts: nil)
    }

    /// Whether the palette shows over the field, which needs the Quick
    /// Window's Space, as the palette's layer does.
    private var isPaletteShown: Bool { chrome?.commandPaletteMode != nil && model.spaceModel != nil }

    /// Opens the palette over the field, starting at the page's address;
    /// without one the field edits in place.
    private var openPalette: (() -> Void)? {
        guard let chrome else { return nil }
        return { [model] in chrome.openLocation(model.address) }
    }

    // MARK: - Actions - Address

    /// What a click on the field's surface does where nothing in the field
    /// takes it, such as the band above and below the address: what a click
    /// on the address does. An address being edited keeps its edit.
    private func openFromSurface() {
        guard !isAddressEditing else { return }
        if let openPalette {
            openPalette()
        } else {
            isAddressEditing = true
        }
    }

    // MARK: - Actions - Page

    private func openAddress() {
        guard let space = model.spaceModel,
            let resolved = try? model.browser.core.query(
                ResolveAddress(workspaceID: model.browser.family.workspaceID, spaceID: space.id, input: addressText)),
            let url = resolved.url.flatMap(URL.init(address:))
        else { return }
        addressText = url.absoluteString
        model.open(url, isActive: scenePhase == .active)
    }

    private func reloadOrStop() {
        model.recordUserActivity()
        model.page?.performReload(.standard)
    }
}

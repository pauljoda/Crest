import SwiftUI

struct BrowserQuickWindowAddressControl: View {
    let model: BrowserQuickWindowModel
    @Binding var addressText: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 7) {
            BrowserQuickWindowSourceSpaceIndicator(space: model.space)
            Divider().frame(height: 16)
            BrowserQuickWindowAddressSecurityIcon(
                isSecure: model.page?.hasOnlySecureContent == true
            )
            BrowserAddressContent(
                text: $addressText,
                isEditing: $isAddressEditing,
                focusRequest: addressFocusRequest,
                activate: nil,
                editorAccessibilityLabel: "Quick Window address",
                editorAccessibilityIdentifier: "quick-window-address",
                summaryAccessibilityIdentifier: "quick-window-address-display",
                prompt: "Search or enter a website",
                submit: openAddress
            )
            .padding(.vertical, BrowserQuickWindowLayout.addressVerticalPadding)
            BrowserQuickWindowAddressTrailingControl(
                page: model.page,
                addressText: $addressText,
                isAddressEditing: isAddressEditing,
                reloadOrStop: reloadOrStop
            )
        }
        .browserAddressFieldSurface(
            progress: model.page?.estimatedProgress ?? 0,
            isLoading: model.page?.isLoading == true,
            isEditing: isAddressEditing
        )
        .frame(
            minWidth: BrowserQuickWindowLayout.addressMinimumWidth,
            maxWidth: .infinity
        )
    }

    private func openAddress() {
        guard let space = model.space,
            let url = AddressResolver.resolve(
                addressText,
                searchProvider: space.browsingPreferences.searchProvider
            )
        else { return }
        addressText = url.absoluteString
        model.open(url, isActive: scenePhase == .active)
    }

    private func reloadOrStop() {
        model.recordUserActivity()
        model.page?.performReload(.standard)
    }
}

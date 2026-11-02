import SwiftUI

struct BrowserQuickWindowToolbar: View {
    let model: BrowserQuickWindowModel
    @Binding var addressText: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        HStack(spacing: BrowserQuickWindowLayout.toolbarSpacing) {
            BrowserQuickWindowNavigationControls(model: model)
            BrowserQuickWindowFieldLayout(
                fieldMinimumWidth: BrowserQuickWindowLayout.addressMinimumWidth,
                widthBeforeExtensions: BrowserQuickWindowLayout.addressWidthBeforeExtensions,
                spacing: BrowserQuickWindowLayout.toolbarSpacing
            ) {
                BrowserQuickWindowAddressControl(
                    model: model,
                    addressText: $addressText,
                    isAddressEditing: $isAddressEditing,
                    addressFocusRequest: addressFocusRequest
                )
                // The field sits under the title bar. A drag across it selects
                // its text, while the strip around it still moves the window.
                .background {
                    BrowserWindowTitleBarControlArea()
                        .accessibilityHidden(true)
                }
                if let space = model.spaceModel {
                    BrowserEngineToolbarAccessory(page: model.page, space: space, browser: model.browser)
                }
            }
            .layoutPriority(1)
            BrowserPeekDestinationControl(
                spaces: model.availableSpaceModels.map(\.identity),
                selectedSpaceID: model.selectedAssignment.spaceID,
                style: .toolbar,
                openInSpace: promote
            )
            // Names the Space while there is room, and is cut short before
            // the address field gives up its minimum.
            .layoutPriority(1)
        }
        .padding(.leading, BrowserQuickWindowLayout.windowControlClearance)
        .padding(.trailing, BrowserQuickWindowLayout.horizontalPadding)
        .padding(.top, BrowserQuickWindowLayout.toolbarTopPadding)
        .frame(maxWidth: .infinity)
        .frame(height: BrowserQuickWindowLayout.toolbarHeight)
    }
}

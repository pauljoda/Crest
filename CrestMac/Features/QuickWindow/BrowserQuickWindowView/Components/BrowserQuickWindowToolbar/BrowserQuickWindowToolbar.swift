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
            BrowserQuickWindowAddressControl(
                model: model,
                addressText: $addressText,
                isAddressEditing: $isAddressEditing,
                addressFocusRequest: addressFocusRequest
            )
            .layoutPriority(1)
            // The field sits under the title bar. A drag across it selects
            // its text, while the strip around it still moves the window.
            .background {
                BrowserWindowTitleBarControlArea()
                    .accessibilityHidden(true)
            }
            BrowserPeekDestinationControl(
                spaces: model.availableSpaceModels.map(\.identity),
                selectedSpaceID: model.selectedAssignment.spaceID,
                style: .toolbar,
                openInSpace: promote
            )
            .fixedSize()
        }
        .padding(.leading, BrowserQuickWindowLayout.windowControlClearance)
        .padding(.trailing, BrowserQuickWindowLayout.horizontalPadding)
        .padding(.top, BrowserQuickWindowLayout.toolbarTopPadding)
        .frame(maxWidth: .infinity)
        .frame(height: BrowserQuickWindowLayout.toolbarHeight)
    }
}

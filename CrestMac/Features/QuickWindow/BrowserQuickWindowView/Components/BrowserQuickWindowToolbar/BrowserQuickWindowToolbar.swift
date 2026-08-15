import SwiftUI

struct BrowserQuickWindowToolbar: View {
    let model: BrowserQuickWindowModel
    @Binding var addressText: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let promote: (BrowserSpace) -> Void

    var body: some View {
        HStack(spacing: BrowserQuickWindowLayout.toolbarSpacing) {
            BrowserQuickWindowAddressControl(
                model: model,
                addressText: $addressText,
                isAddressEditing: $isAddressEditing,
                addressFocusRequest: addressFocusRequest
            )
            .layoutPriority(1)
            BrowserQuickWindowDestinationControl(
                model: model,
                promote: promote
            )
        }
        .padding(.leading, BrowserQuickWindowLayout.windowControlClearance)
        .padding(.trailing, BrowserQuickWindowLayout.horizontalPadding)
        .padding(.vertical, BrowserQuickWindowLayout.toolbarVerticalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: BrowserQuickWindowLayout.toolbarHeight)
    }
}

#Preview("Quick Window Toolbar") {
    @Previewable @State var addressText = ""
    @Previewable @State var isEditing = false
    BrowserQuickWindowToolbar(
        model: BrowserQuickWindowPreviewFixture.makeModel(),
        addressText: $addressText,
        isAddressEditing: $isEditing,
        addressFocusRequest: 0,
        promote: { _ in }
    )
    .frame(width: 640)
}

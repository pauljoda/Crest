import SwiftUI

struct BrowserQuickWindowDestinationPickerButton: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    @Binding var isPresented: Bool
    let promote: (BrowserSpace) -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: CGSize(
                    width: BrowserQuickWindowLayout.minimumMacHitTarget,
                    height: BrowserQuickWindowLayout.controlHeight
                ),
                cornerRadius: CrestRadius.compact
            )
        )
        .accessibilityLabel("Choose Destination Space")
        .accessibilityIdentifier("quick-window-destination-space-picker")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            BrowserQuickWindowSpacePicker(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID
            ) { candidate in
                isPresented = false
                promote(candidate)
            }
        }
    }
}

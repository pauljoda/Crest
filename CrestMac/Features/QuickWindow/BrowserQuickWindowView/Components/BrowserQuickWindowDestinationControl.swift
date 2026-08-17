import SwiftUI

struct BrowserQuickWindowDestinationControl: View {
    let model: BrowserQuickWindowModel
    let promote: (BrowserSpace) -> Void

    @State private var isPickerPresented = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: promoteCurrentSpace) {
                Text(
                    BrowserQuickWindowChromePolicy.destinationTitle(
                        spaceName: model.space?.name ?? "Space"
                    )
                )
                .lineLimit(1)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: BrowserQuickWindowLayout.controlHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityIdentifier("quick-window-open-destination")
            BrowserQuickWindowDestinationPickerButton(
                spaces: model.availableSpaces,
                selectedSpaceID: model.selectedAssignment.spaceID,
                isPresented: $isPickerPresented,
                promote: promote
            )
        }
        .font(.callout.weight(.semibold))
        .background(
            CrestColor.chromeSurface,
            in: .rect(
                cornerRadius: BrowserChromeLayout.addressCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: BrowserChromeLayout.addressCornerRadius,
                style: .continuous
            )
            .strokeBorder(CrestColor.subtleBorder, lineWidth: 0.5)
        }
        .fixedSize()
        .help("Open in \(model.space?.name ?? "Space") (⌘O)")
    }

    private func promoteCurrentSpace() {
        guard let space = model.space else { return }
        promote(space)
    }
}

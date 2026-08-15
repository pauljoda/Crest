import SwiftUI

struct BrowserPeekActionControls: View {
    let model: BrowserPeekModel
    let dismiss: () -> Void
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        BrowserPeekActionBar(
            spaces: model.availableSpaces,
            selectedSpaceID: model.request.spaceID,
            closeAccessibilityLabel: "Close Peek",
            closeHelp: "Close Peek (Esc or ⌘W)",
            dismiss: dismiss,
            openInSpace: promote
        )
        .frame(width: BrowserPeekChromePolicy.controlBarWidth)
    }
}

#Preview {
    BrowserPeekActionControls(
        model: BrowserPeekPreviewFixture.makeModel(),
        dismiss: {},
        promote: { _ in }
    )
    .padding()
}

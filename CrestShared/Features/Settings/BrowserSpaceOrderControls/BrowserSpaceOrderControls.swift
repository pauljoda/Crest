import SwiftUI

struct BrowserSpaceOrderControls: View {
    let browser: BrowserStore
    let spaceID: SpaceID?

    var body: some View {
        let actions = BrowserSpaceOrderActions(browser: browser, spaceID: spaceID)
        HStack(spacing: 0) {
            Button("Move Up", systemImage: "arrow.up", action: actions.moveUp)
                .disabled(!actions.canMoveUp)
                .help("Move Up")
                .accessibilityIdentifier("space-settings-move-up")
            Divider()
            Button("Move Down", systemImage: "arrow.down", action: actions.moveDown)
                .disabled(!actions.canMoveDown)
                .help("Move Down")
                .accessibilityIdentifier("space-settings-move-down")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CrestChromeButtonStyle(cornerRadius: 0))
        .frame(height: CrestLayout.minimumHitTarget)
        .background(BrowserSettingsCanvas.background)
        .clipShape(.rect(cornerRadius: CrestRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: CrestRadius.control)
                .strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }
}

import SwiftUI

struct BrowserSpaceOrderControls: View {
    let browser: BrowserStore
    let spaceID: UUID?

    var body: some View {
        let actions = BrowserSpaceOrderActions(browser: browser, spaceID: spaceID)
        HStack(spacing: CrestSpacing.small) {
            BrowserSpaceSettingsIconButton(title: "Move Up", symbol: "arrow.up", action: actions.moveUp)
                .disabled(!actions.canMoveUp)
                .help("Move Up")
                .accessibilityIdentifier("space-settings-move-up")
            BrowserSpaceSettingsIconButton(title: "Move Down", symbol: "arrow.down", action: actions.moveDown)
                .disabled(!actions.canMoveDown)
                .help("Move Down")
                .accessibilityIdentifier("space-settings-move-down")
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }
}

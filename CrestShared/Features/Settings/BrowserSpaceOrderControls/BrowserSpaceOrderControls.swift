import SwiftUI

struct BrowserSpaceOrderControls: View {
    let browser: BrowserStore
    let spaceID: SpaceID?
    @Namespace private var glassNamespace

    private enum GlassGroup { case order }

    var body: some View {
        let actions = BrowserSpaceOrderActions(browser: browser, spaceID: spaceID)
        GlassEffectContainer {
            HStack(spacing: 0) {
                BrowserSpaceSettingsGlassButton(title: "Move Up", symbol: "arrow.up", action: actions.moveUp)
                    .glassEffectUnion(id: GlassGroup.order, namespace: glassNamespace)
                    .disabled(!actions.canMoveUp)
                    .help("Move Up")
                    .accessibilityIdentifier("space-settings-move-up")
                BrowserSpaceSettingsGlassButton(title: "Move Down", symbol: "arrow.down", action: actions.moveDown)
                    .glassEffectUnion(id: GlassGroup.order, namespace: glassNamespace)
                    .disabled(!actions.canMoveDown)
                    .help("Move Down")
                    .accessibilityIdentifier("space-settings-move-down")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }
}

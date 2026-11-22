import SwiftUI

/// A Space's Appearance page: its crest or icon on the Space's own field
/// beside its colors, its icon, and More Customization.
struct BrowserSpaceEditorView: View {
    @Environment(\.browserSettingsTabState) private var tabState
    @State private var standaloneStep = BrowserCrestStudioStep.shape

    let browser: BrowserStore
    let space: SpaceModel

    var body: some View {
        BrowserCrestForge(branding: branding, symbol: symbol, step: forgeStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("space-customization-controls")
    }

    private var forgeStep: Binding<BrowserCrestStudioStep> {
        Binding(
            get: { tabState?.forgeStep ?? standaloneStep },
            set: { if let tabState { tabState.forgeStep = $0 } else { standaloneStep = $0 } })
    }

    private var symbol: Binding<String> {
        browser.spaceSymbolBinding(in: space)
    }

    private var branding: Binding<SpaceBranding> {
        browser.spaceBrandingBinding(in: space)
    }
}

import SwiftUI

/// Chooses between a simple SF Symbol and the layered crest editor.
struct BrowserSpaceMarkStep: View {
    @Binding var branding: BrowserSpaceBranding
    @Binding var symbol: String
    let compact: Bool

    var body: some View {
        BrowserSpaceForgeSection(
            step: .mark,
            value: branding.iconStyle.title,
            caption: "How this Space signs itself in the sidebar and on its tabs."
        ) {
            Picker("Space icon", selection: $branding.editorIconStyle) {
                ForEach(BrowserSpaceIconStyle.allCases, id: \.self) { style in
                    Text(style.titleKey).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .tint(CrestBrandTheme.accent)

            if branding.iconStyle == .layeredCrest {
                BrowserSpaceCrestArtifactPreview(
                    branding: branding,
                    compact: compact
                )
            } else {
                BrowserSpaceSimpleSymbolPicker(symbol: $symbol)
            }
        }
    }
}

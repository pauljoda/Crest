import SwiftUI

struct BrowserSpaceTrimStep: View {
    @Binding var branding: BrowserSpaceBranding
    let compact: Bool

    var body: some View {
        BrowserSpaceForgeSection(
            step: .trim,
            value: branding.crest.trim.title,
            caption: "The outer finish. Keep it quiet so the shield survives being small."
        ) {
            BrowserSpaceCrestOptionGallery(
                branding: $branding,
                options: BrowserSpaceCrestTrim.allCases,
                keyPath: \.trim,
                compact: compact
            )

            if branding.crest.trim != .none {
                BrowserSpaceLayerColorPicker(
                    title: "Trim color",
                    branding: branding,
                    selection: $branding.editorTrimColorIndex
                )
            }
        }
    }
}

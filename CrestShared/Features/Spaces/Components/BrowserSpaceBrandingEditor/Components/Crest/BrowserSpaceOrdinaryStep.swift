import SwiftUI

struct BrowserSpaceOrdinaryStep: View {
    @Binding var branding: BrowserSpaceBranding
    let compact: Bool

    var body: some View {
        BrowserSpaceForgeSection(
            step: .ordinary,
            value: branding.crest.ordinary.title,
            caption: "One bold band across the field. Restraint reads better than a second idea."
        ) {
            BrowserSpaceCrestOptionGallery(
                branding: $branding,
                options: BrowserSpaceCrestOrdinary.allCases,
                keyPath: \.ordinary,
                compact: compact
            )

            if branding.crest.ordinary != .none {
                BrowserSpaceLayerColorPicker(
                    title: "Ordinary color",
                    branding: branding,
                    selection: $branding.editorOrdinaryColorIndex
                )
            }
        }
    }
}

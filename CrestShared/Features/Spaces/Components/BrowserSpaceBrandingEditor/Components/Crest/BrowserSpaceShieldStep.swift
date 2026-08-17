import SwiftUI

struct BrowserSpaceShieldStep: View {
    @Binding var branding: BrowserSpaceBranding
    let compact: Bool

    var body: some View {
        BrowserSpaceForgeSection(
            step: .shield,
            value: branding.crest.backplate.title,
            caption: "The shape the arms are borne on."
        ) {
            BrowserSpaceCrestOptionGallery(
                branding: $branding,
                options: BrowserSpaceCrestBackplate.allCases,
                keyPath: \.backplate,
                compact: compact
            )
        }
    }
}

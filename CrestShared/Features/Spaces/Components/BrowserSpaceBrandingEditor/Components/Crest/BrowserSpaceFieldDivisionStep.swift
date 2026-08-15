import SwiftUI

struct BrowserSpaceFieldDivisionStep: View {
    @Binding var branding: BrowserSpaceBranding
    let compact: Bool

    var body: some View {
        BrowserSpaceForgeSection(
            step: .division,
            value: branding.crest.fieldDivision.title,
            caption: "How the shield's field is divided."
        ) {
            BrowserSpaceCrestOptionGallery(
                branding: $branding,
                options: BrowserSpaceCrestFieldDivision.allCases,
                keyPath: \.fieldDivision,
                compact: compact
            )

            BrowserSpaceLayerColorPicker(
                title: "Field color",
                branding: branding,
                selection: $branding.editorBackplateColorIndex
            )
            if branding.crest.fieldDivision != .plain {
                BrowserSpaceLayerColorPicker(
                    title: "Second field color",
                    branding: branding,
                    selection: $branding.editorSecondaryFieldColorIndex
                )
            }
        }
    }
}

#Preview("Branding Editor — Field Division Step") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding

    ScrollView {
        BrowserSpaceFieldDivisionStep(
            branding: $branding,
            compact: false
        )
        .padding(CrestSpacing.large)
    }
    .frame(width: 620, height: 600)
}

import SwiftUI

struct BrowserSpaceChargeStep: View {
    @Binding var branding: BrowserSpaceBranding
    let compact: Bool

    var body: some View {
        BrowserSpaceForgeSection(
            step: .charge,
            value: branding.crest.symbol.title,
            caption: "The single figure these arms are known by. It has to read at tab size."
        ) {
            BrowserSpaceCrestOptionGallery(
                branding: $branding,
                options: BrowserSpaceCrestSymbol.selectable,
                keyPath: \.symbol,
                compact: compact,
                regularMinimumWidth: BrowserSpaceForgeMetrics.chargeCardMinimumWidth,
                compactMinimumWidth: BrowserSpaceForgeMetrics.compactChargeCardMinimumWidth,
                iconSize: BrowserSpaceForgeMetrics.chargeThumbnailSize
            )

            LabeledContent("Number of charges") {
                Picker(
                    "Number of charges",
                    selection: $branding.editorChargeLayout
                ) {
                    ForEach(BrowserSpaceCrestChargeLayout.allCases, id: \.self) { layout in
                        Text(layout.titleKey).tag(layout)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .tint(CrestBrandTheme.accent)
                .frame(maxWidth: BrowserSpaceForgeMetrics.chargeLayoutMaximumWidth)
            }

            BrowserSpaceLayerColorPicker(
                title: "Charge color",
                branding: branding,
                selection: $branding.editorSymbolColorIndex
            )
        }
    }
}

#Preview("Branding Editor — Charge Step") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding

    ScrollView {
        BrowserSpaceChargeStep(
            branding: $branding,
            compact: false
        )
        .padding(CrestSpacing.large)
    }
    .frame(width: 620, height: 680)
}

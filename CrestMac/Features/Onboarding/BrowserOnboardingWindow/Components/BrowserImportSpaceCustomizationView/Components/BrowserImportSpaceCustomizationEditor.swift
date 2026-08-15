import SwiftUI

struct BrowserImportSpaceCustomizationEditor: View {
    let previewSpace: BrowserSpace?
    @Binding var name: String
    @Binding var symbol: String
    @Binding var branding: BrowserSpaceBranding

    var body: some View {
        HStack(alignment: .top, spacing: 44) {
            BrowserImportSpaceCustomizationPreviewPane(space: previewSpace)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        TextField("Space name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                    }

                    BrowserSpaceBrandingEditor(
                        branding: $branding,
                        symbol: $symbol,
                        compact: true,
                        showsPreview: false
                    )
                }
                .padding(.bottom, 32)
            }
            .frame(maxWidth: 640)
        }
        .frame(maxWidth: 1_080, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 38)
        .padding(.vertical, 28)
        .background(BrowserOnboardingPalette.parchment)
    }
}

#Preview("Space Customization Editor") {
    @Previewable @State var name = BrowserImportPreviewFixture.sourceSpace.name
    @Previewable @State var symbol = BrowserImportPreviewFixture.sourceSpace.symbol
    @Previewable @State var branding = BrowserImportPreviewFixture.sourceSpace.branding

    BrowserImportSpaceCustomizationEditor(
        previewSpace: BrowserImportPreviewFixture.sourceSpace,
        name: $name,
        symbol: $symbol,
        branding: $branding
    )
    .frame(width: 1_080, height: 650)
}

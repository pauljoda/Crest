import SwiftUI

struct BrowserImportSpaceCustomizationContent: View {
    let previewSpace: BrowserSpace?
    @Binding var name: String
    @Binding var symbol: String
    @Binding var branding: BrowserSpaceBranding
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BrowserImportSpaceCustomizationHeader(done: done)
            BrowserImportSpaceCustomizationEditor(
                previewSpace: previewSpace,
                name: $name,
                symbol: $symbol,
                branding: $branding
            )
        }
    }
}

#Preview("Space Customization Content") {
    @Previewable @State var name = BrowserImportPreviewFixture.sourceSpace.name
    @Previewable @State var symbol = BrowserImportPreviewFixture.sourceSpace.symbol
    @Previewable @State var branding = BrowserImportPreviewFixture.sourceSpace.branding

    BrowserImportSpaceCustomizationContent(
        previewSpace: BrowserImportPreviewFixture.sourceSpace,
        name: $name,
        symbol: $symbol,
        branding: $branding,
        done: {}
    )
    .frame(width: 1_080, height: 720)
}

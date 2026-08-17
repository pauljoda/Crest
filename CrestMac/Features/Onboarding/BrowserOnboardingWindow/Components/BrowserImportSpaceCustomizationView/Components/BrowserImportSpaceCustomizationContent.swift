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

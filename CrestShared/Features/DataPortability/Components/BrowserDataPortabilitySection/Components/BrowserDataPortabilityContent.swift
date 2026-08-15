import SwiftUI

struct BrowserDataPortabilityContent: View {
    let model: BrowserDataPortabilityModel
    let showsExternalBrowserImportControls: Bool
    let showsMacOSImportRequirement: Bool

    var body: some View {
        Section("Import & Export") {
            if showsMacOSImportRequirement {
                BrowserDataPortabilityMacRequirement()
            }
            BrowserDataPortabilityExportControls(model: model)
            if showsExternalBrowserImportControls {
                BrowserDataPortabilityExternalImportControls(model: model)
            }
            BrowserDataPortabilityProgressStatus(model: model)
            BrowserDataPortabilityFootnotes(
                showsExternalBrowserImportControls:
                    showsExternalBrowserImportControls
            )
        }
    }
}

#Preview("Data Portability Content") {
    Form {
        BrowserDataPortabilityContent(
            model: BrowserDataPortabilityPreviewFixture.makeModel(),
            showsExternalBrowserImportControls: true,
            showsMacOSImportRequirement: true
        )
    }
    .frame(width: 680, height: 720)
}

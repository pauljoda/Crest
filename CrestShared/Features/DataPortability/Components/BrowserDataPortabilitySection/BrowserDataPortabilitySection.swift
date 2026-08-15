import SwiftUI

struct BrowserDataPortabilitySection: View {
    @State private var model: BrowserDataPortabilityModel

    let showsExternalBrowserImportControls: Bool
    let showsMacOSImportRequirement: Bool
    private let presentsSystemPanels: Bool

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        showsExternalBrowserImportControls: Bool = true,
        showsMacOSImportRequirement: Bool = false
    ) {
        _model = State(
            initialValue: BrowserDataPortabilityModel(
                browser: browser,
                spaceAccess: spaceAccess
            )
        )
        self.showsExternalBrowserImportControls =
            showsExternalBrowserImportControls
        self.showsMacOSImportRequirement = showsMacOSImportRequirement
        presentsSystemPanels = true
    }

    init(
        model: BrowserDataPortabilityModel,
        showsExternalBrowserImportControls: Bool = true,
        showsMacOSImportRequirement: Bool = false,
        presentsSystemPanels: Bool = false
    ) {
        _model = State(initialValue: model)
        self.showsExternalBrowserImportControls =
            showsExternalBrowserImportControls
        self.showsMacOSImportRequirement = showsMacOSImportRequirement
        self.presentsSystemPanels = presentsSystemPanels
    }

    var body: some View {
        BrowserDataPortabilityDocumentPresenter(
            model: model,
            presentsSystemPanels: presentsSystemPanels
        ) {
            BrowserDataPortabilityContent(
                model: model,
                showsExternalBrowserImportControls:
                    showsExternalBrowserImportControls,
                showsMacOSImportRequirement: showsMacOSImportRequirement
            )
        }
        .onChange(of: model.lockedSpaceIDs) { _, spaceIDs in
            if !spaceIDs.isEmpty {
                model.cancelSensitiveExports()
            }
        }
    }
}

#Preview("Data Portability") {
    BrowserDataPortabilitySection(
        model: BrowserDataPortabilityPreviewFixture.makeModel(),
        showsExternalBrowserImportControls: true,
        showsMacOSImportRequirement: true
    )
    .frame(width: 680, height: 720)
}

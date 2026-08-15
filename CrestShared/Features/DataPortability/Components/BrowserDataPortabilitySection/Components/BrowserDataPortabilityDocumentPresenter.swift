import SwiftUI
import UniformTypeIdentifiers

struct BrowserDataPortabilityDocumentPresenter<Content: View>: View {
    @Bindable var model: BrowserDataPortabilityModel
    let presentsSystemPanels: Bool
    let content: Content

    init(
        model: BrowserDataPortabilityModel,
        presentsSystemPanels: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.presentsSystemPanels = presentsSystemPanels
        self.content = content()
    }

    var body: some View {
        if presentsSystemPanels {
            content
                .fileExporter(
                    isPresented: $model.isExporting,
                    document: model.exportDocument,
                    contentType: .json,
                    defaultFilename: BrowserPortableArchive.defaultFilename,
                    onCompletion: model.finishPortableExport
                )
                .fileImporter(
                    isPresented: $model.isImporting,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false,
                    onCompletion: model.finishPortableImport
                )
                .fileExporter(
                    isPresented: $model.isExportingBookmarks,
                    document: model.bookmarkExportDocument,
                    contentType: .html,
                    defaultFilename: BrowserBookmarkMigration.defaultHTMLFilename,
                    onCompletion: model.finishBookmarkExport
                )
                .fileImporter(
                    isPresented: $model.isImportingBookmarks,
                    allowedContentTypes:
                        model.bookmarkImportSource?.allowedContentTypes ?? [.data],
                    allowsMultipleSelection: false,
                    onCompletion: model.finishBookmarkImport
                )
                .fileImporter(
                    isPresented: $model.isImportingHistory,
                    allowedContentTypes: [.data],
                    allowsMultipleSelection: false,
                    onCompletion: model.finishHistoryImport
                )
                .fileImporter(
                    isPresented: $model.isImportingTabs,
                    allowedContentTypes:
                        model.tabImportSource?.allowedContentTypes ?? [.data],
                    allowsMultipleSelection: false,
                    onCompletion: model.finishTabImport
                )
        } else {
            content
        }
    }
}

#Preview("Document Presentation Shell") {
    BrowserDataPortabilityDocumentPresenter(
        model: BrowserDataPortabilityPreviewFixture.makeModel(),
        presentsSystemPanels: false
    ) {
        Text("Import & Export")
            .padding()
    }
}

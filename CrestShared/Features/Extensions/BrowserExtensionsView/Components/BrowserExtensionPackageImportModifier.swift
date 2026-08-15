import SwiftUI
import UniformTypeIdentifiers

struct BrowserExtensionPackageImportModifier: ViewModifier {
    @Bindable var model: BrowserExtensionsModel

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $model.isChoosingExtension,
            allowedContentTypes: [.folder, .zip],
            allowsMultipleSelection: false
        ) { result in
            Task { await model.importExtension(from: result) }
        }
    }
}

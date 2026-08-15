import SwiftUI
import UniformTypeIdentifiers

struct BrowserSafariExtensionImportModifier: ViewModifier {
    @Bindable var model: BrowserExtensionDiscoveryModel

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $model.isChoosingSafariApplication,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: false
        ) { result in
            Task { await model.inspectSafariApplication(from: result) }
        }
    }
}

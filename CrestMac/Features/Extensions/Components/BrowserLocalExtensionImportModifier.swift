import SwiftUI
import UniformTypeIdentifiers

struct BrowserLocalExtensionImportModifier: ViewModifier {
    @Bindable var session: BrowserLocalExtensionInstallSession

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $session.isChoosingPackage,
            allowedContentTypes: [.crestChromeCRX, .crestFirefoxXPI],
            allowsMultipleSelection: false
        ) { result in
            Task { await session.prepare(from: result) }
        }
        .fileDialogMessage(
            "Choose a Chrome CRX or Firefox XPI extension package."
        )
        .fileDialogConfirmationLabel("Review Package")
    }
}

extension UTType {
    fileprivate static let crestChromeCRX = UTType(
        importedAs: "com.google.chrome.crx",
        conformingTo: .data
    )
    fileprivate static let crestFirefoxXPI = UTType(
        importedAs: "org.mozilla.firefox.xpi",
        conformingTo: .zip
    )
}

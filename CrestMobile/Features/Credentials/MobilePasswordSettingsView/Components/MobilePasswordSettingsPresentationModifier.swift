import SwiftUI
import UniformTypeIdentifiers

struct MobilePasswordSettingsPresentationModifier: ViewModifier {
    @Bindable var model: MobilePasswordSettingsModel

    func body(content: Content) -> some View {
        content
            .alert(
                "Delete Password?",
                isPresented: $model.deletionAlertIsPresented,
                presenting: model.pendingDeletion
            ) { descriptor in
                Button("Delete", role: .destructive) {
                    model.delete(descriptor)
                }
                Button("Cancel", role: .cancel) {}
            } message: { descriptor in
                Text(
                    model.credentials.deletionMessage(
                        for: descriptor,
                        in: model.selectedSpace
                    )
                )
            }
            .alert(
                "Export Passwords as Plaintext?",
                isPresented: $model.confirmsPlaintextExport
            ) {
                Button("Export…", action: model.prepareExport)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The CSV file will contain readable usernames and passwords from only the selected Space. Anyone with the file can read them. Crest will authenticate you before opening the Files picker."
                )
            }
            .sheet(item: $model.credentialDetailRequest) { request in
                BrowserCredentialDetailView(
                    browser: model.browser,
                    spaceAccess: model.spaceAccess,
                    request: request
                )
                .id(request.id)
                .presentationDetents([.medium, .large])
            }
            .fileExporter(
                isPresented: $model.isExporting,
                document: model.credentials.exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: model.credentials.exportFilename
            ) { result in
                if case .failure = result {
                    model.finishExport(didFail: true)
                } else {
                    model.finishExport(didFail: false)
                }
            }
    }
}

#Preview {
    let fixture = MobileBrowserPreviewFixture()
    let model = MobilePasswordSettingsModel(
        browser: fixture.browser,
        spaceAccess: fixture.spaceAccess
    )
    Text("Passwords")
        .modifier(MobilePasswordSettingsPresentationModifier(model: model))
}

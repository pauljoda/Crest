import SwiftUI

/// A saved login in a sheet over Settings, to look at and edit.
struct BrowserCredentialDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.browserCodeScanning) private var scanning
    @State private var model: BrowserCredentialDetailModel
    private var browser: BrowserStore?
    var changePasswordOnWebsite: ((CredentialOrigin) -> Void)? = nil
    var delete: (() -> Void)? = nil

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        request: BrowserCredentialDetailRequest,
        changePasswordOnWebsite: ((CredentialOrigin) -> Void)? = nil,
        delete: (() -> Void)? = nil
    ) {
        self.changePasswordOnWebsite = changePasswordOnWebsite
        self.delete = delete
        self.browser = browser
        _model = State(
            initialValue: BrowserCredentialDetailModel(
                browser: browser,
                spaceAccess: spaceAccess,
                request: request
            )
        )
    }

    init(
        request _: BrowserCredentialDetailRequest,
        model: BrowserCredentialDetailModel
    ) {
        _model = State(initialValue: model)
    }

    /// A snapshot of the login's site where it is open in the Space.
    private var scanPage: (() async -> CGImage?)? {
        guard let scan = scanning.scanPage else { return nil }
        let spaceID = model.spaceAssignment.spaceID
        let origin = model.descriptor.origin
        return { await scan(spaceID, origin) }
    }

    var body: some View {
        NavigationStack {
            BrowserCredentialDetailContent(
                model: model,
                dismiss: dismiss.callAsFunction,
                changePasswordOnWebsite: changePasswordOnWebsite,
                delete: delete,
                browser: browser,
                scanPage: scanPage,
                scanWithCamera: scanning.scanWithCamera
            )
        }
        .crestSheetSize(minWidth: 420, idealWidth: 480, minHeight: 420, idealHeight: 560)
        .task(id: model.revealExpiration) {
            guard let expiration = model.revealExpiration else { return }
            await model.expireReveal(at: expiration)
        }
        .task(id: model.copyExpiration) {
            guard let expiration = model.copyExpiration else { return }
            await model.expireCopyConfirmation(at: expiration)
        }
        .onDisappear(perform: model.clearSensitiveState)
    }
}

#Preview("Credential Detail") {
    BrowserCredentialDetailView(
        request: BrowserCredentialDetailPreviewFixture.request,
        model: BrowserCredentialDetailPreviewFixture.makeModel()
    )
}

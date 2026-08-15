import SwiftUI

struct MobilePasswordSettingsContent: View {
    @Bindable var model: MobilePasswordSettingsModel
    let passkeyAccess: BrowserPasskeyAccessController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            MobilePasswordSpaceSection(model: model)
            MobilePasswordDataSections(model: model)
            MobilePasswordSystemPasskeysSection(access: passkeyAccess)
        }
        .navigationTitle("Passwords")
        .searchable(text: $model.searchText, prompt: "Search accounts or sites")
        .toolbar {
            MobilePasswordSettingsToolbar(
                model: model,
                dismiss: dismiss.callAsFunction
            )
        }
        .crestRepairsSpaceSelection($model.selectedSpaceID, in: model.browser)
        .task(id: model.credentialLoadRequest) {
            await model.loadCredentials()
        }
        .onChange(of: model.credentialLoadRequest, initial: true) { previous, request in
            model.handleCredentialLoadRequest(previous: previous, request)
        }
    }
}

#Preview {
    let fixture = MobileBrowserPreviewFixture()
    let model = MobilePasswordSettingsModel(
        browser: fixture.browser,
        spaceAccess: fixture.spaceAccess
    )
    NavigationStack {
        MobilePasswordSettingsContent(
            model: model,
            passkeyAccess: fixture.passkeyAccess
        )
    }
}

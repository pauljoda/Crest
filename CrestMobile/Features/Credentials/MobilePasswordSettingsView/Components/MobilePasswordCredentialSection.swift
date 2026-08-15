import SwiftUI

struct MobilePasswordCredentialSection: View {
    @Bindable var model: MobilePasswordSettingsModel

    var body: some View {
        Section("Crest Passwords") {
            if let selectedSpace = model.selectedSpace {
                Toggle(
                    "Sync this Space’s Crest passwords with iCloud Keychain",
                    isOn: model.credentials.synchronizationBinding(
                        in: selectedSpace,
                        accessController: model.spaceAccess
                    )
                )
                .disabled(model.credentials.isChangingSynchronization)
            }

            if model.credentials.isChangingSynchronization {
                ProgressView("Updating this Space’s saved passwords…")
            }

            MobilePasswordDescriptorList(model: model)
        }
    }
}

#Preview {
    let fixture = MobileBrowserPreviewFixture()
    let model = MobilePasswordSettingsModel(
        browser: fixture.browser,
        spaceAccess: fixture.spaceAccess
    )
    Form {
        MobilePasswordCredentialSection(model: model)
    }
}

import SwiftUI

struct MobilePasswordSpaceSection: View {
    @Bindable var model: MobilePasswordSettingsModel

    var body: some View {
        Section("Space") {
            CrestSpaceMenuPicker(
                "Passwords in",
                selection: $model.selectedSpaceID,
                spaces: CrestSpaceIdentity.list(model.browser.session.spaces)
            )
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
        MobilePasswordSpaceSection(model: model)
    }
}

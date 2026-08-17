import SwiftUI

/// The full-screen saved-password manager used by the touch settings shell.
struct MobilePasswordSettingsView: View {
    @State private var model: MobilePasswordSettingsModel
    private let passkeyAccess: BrowserPasskeyAccessController

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        passkeyAccess: BrowserPasskeyAccessController =
            BrowserPasskeyAccessController()
    ) {
        _model = State(
            initialValue: MobilePasswordSettingsModel(
                browser: browser,
                spaceAccess: spaceAccess
            )
        )
        self.passkeyAccess = passkeyAccess
    }

    var body: some View {
        NavigationStack {
            MobilePasswordSettingsContent(
                model: model,
                passkeyAccess: passkeyAccess
            )
            .modifier(
                MobilePasswordSettingsPresentationModifier(model: model)
            )
        }
        .presentationDetents([.large])
    }
}

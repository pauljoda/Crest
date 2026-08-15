import SwiftUI

struct MobilePasswordSettingsToolbar: ToolbarContent {
    @Bindable var model: MobilePasswordSettingsModel
    let dismiss: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Export Passwords", systemImage: "square.and.arrow.up") {
                model.confirmsPlaintextExport = true
            }
            .labelStyle(.iconOnly)
            .disabled(
                model.selectedSpace == nil
                    || !model.canRevealSelectedSpaceData
                    || model.credentials.descriptors.isEmpty
                    || model.credentials.isPreparingExport
            )
            .accessibilityIdentifier("export-space-passwords")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: dismiss)
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
        Text("Passwords")
            .toolbar {
                MobilePasswordSettingsToolbar(model: model, dismiss: {})
            }
    }
}

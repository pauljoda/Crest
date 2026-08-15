import SwiftUI

struct BrowserShortcutSettingsView: View {
    @State private var model: BrowserShortcutSettingsModel

    private let requestedSpaceID: SpaceID?
    private let requestedExtensionCommand: BrowserExtensionCommandSettingsRoute?
    private let requestRevision: Int

    init(
        shortcuts: BrowserShortcutStore,
        browser: BrowserStore,
        extensionControllerPool: BrowserExtensionControllerPool,
        requestedSpaceID: SpaceID? = nil,
        requestedExtensionCommand:
            BrowserExtensionCommandSettingsRoute? = nil,
        requestRevision: Int = 0
    ) {
        self.init(
            model: BrowserShortcutSettingsModel(
                shortcuts: shortcuts,
                browser: browser,
                extensionCommands: extensionControllerPool,
                searchProvider: BrowserShortcutPresentationCatalog(),
                selectedExtensionSpaceID:
                    requestedSpaceID ?? browser.session.selectedSpaceID
            ),
            requestedSpaceID: requestedSpaceID,
            requestedExtensionCommand: requestedExtensionCommand,
            requestRevision: requestRevision
        )
    }

    init(
        model: BrowserShortcutSettingsModel,
        requestedSpaceID: SpaceID? = nil,
        requestedExtensionCommand:
            BrowserExtensionCommandSettingsRoute? = nil,
        requestRevision: Int = 0
    ) {
        _model = State(initialValue: model)
        self.requestedSpaceID = requestedSpaceID
        self.requestedExtensionCommand = requestedExtensionCommand
        self.requestRevision = requestRevision
    }

    var body: some View {
        BrowserShortcutSettingsContent(
            model: model,
            requestedSpaceID: requestedSpaceID,
            requestedExtensionCommand: requestedExtensionCommand,
            requestRevision: requestRevision
        )
    }
}

#Preview("Keyboard Shortcuts") {
    BrowserShortcutSettingsView(
        model: BrowserShortcutSettingsPreviewFactory.model()
    )
    .frame(
        width: BrowserShortcutSettingsMetrics.maximumContentWidth,
        height: BrowserShortcutSettingsMetrics.previewHeight
    )
}

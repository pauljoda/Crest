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

private struct BrowserShortcutSettingsContent: View {
    @Environment(\.locale) private var locale
    @Bindable var model: BrowserShortcutSettingsModel
    @State private var showsResetConfirmation = false

    let requestedSpaceID: SpaceID?
    let requestedExtensionCommand: BrowserExtensionCommandSettingsRoute?
    let requestRevision: Int

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserShortcutSettingsMetrics.contentSpacing
        ) {
            BrowserShortcutSettingsControls(
                searchText: $model.searchText,
                selectedExtensionSpaceID: $model.selectedExtensionSpaceID,
                spaces: model.spaces,
                canReset: model.hasCrestCustomizations,
                requestReset: { showsResetConfirmation = true }
            )

            if let issue = model.validationIssue {
                BrowserShortcutValidationBanner(issue: issue)
            }

            BrowserShortcutList(model: model)

            Text(BrowserShortcutSettingsPresentation.guidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: BrowserShortcutSettingsMetrics.maximumContentWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .alert(
            BrowserShortcutSettingsPresentation.shortcutAlreadyInUse,
            isPresented: $model.isPresentingConflict
        ) {
            Button(
                BrowserShortcutSettingsPresentation.replaceExistingShortcut,
                action: model.replacePendingConflict
            )
            Button(
                BrowserShortcutSettingsPresentation.cancel,
                role: .cancel,
                action: model.cancelPendingConflict
            )
        } message: {
            Text(
                model.pendingConflict?.messageResource(locale: locale)
                    ?? BrowserShortcutLocalization.resource(
                        BrowserShortcutSettingsPresentation
                            .chooseAnotherShortcut,
                        locale: locale
                    )
            )
        }
        .confirmationDialog(
            BrowserShortcutSettingsPresentation.resetAllPrompt,
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                BrowserShortcutSettingsPresentation.resetCrestShortcuts,
                role: .destructive,
                action: model.resetAllCrestShortcuts
            )
        } message: {
            Text(BrowserShortcutSettingsPresentation.resetAllDetail)
        }
        .onChange(of: locale.identifier, initial: true) {
            model.updateSearchProvider(
                BrowserShortcutPresentationCatalog(locale: locale)
            )
        }
        .onChange(of: requestRevision, initial: true) {
            model.applyDeepLink(
                requestedSpaceID: requestedSpaceID,
                extensionID: requestedExtensionCommand?.extensionID,
                commandID: requestedExtensionCommand?.commandID,
                revision: requestRevision
            )
        }
    }
}

private struct BrowserShortcutValidationBanner: View {
    @Environment(\.locale) private var locale

    let issue: BrowserShortcutValidationIssue

    var body: some View {
        Label(
            issue.messageResource(locale: locale),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .accessibilityIdentifier(
            BrowserShortcutSettingsAccessibilityID.validationMessage
        )
    }
}

import SwiftUI

struct BrowserShortcutSettingsContent: View {
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

#Preview("Shortcut Settings Content") {
    BrowserShortcutSettingsContent(
        model: BrowserShortcutSettingsPreviewFactory.model(),
        requestedSpaceID: nil,
        requestedExtensionCommand: nil,
        requestRevision: 0
    )
    .frame(
        width: BrowserShortcutSettingsMetrics.maximumContentWidth,
        height: BrowserShortcutSettingsMetrics.previewHeight
    )
}

import SwiftUI

/// Space-scoped WebExtension management shared by both Settings shells.
struct BrowserExtensionsView: View {
    @State private var model: BrowserExtensionsModel
    private let platformActions: BrowserExtensionPlatformActions
    /// Absent on a shell that has no way to install a replacement package, in
    /// which case the updates section has nothing to offer and stays hidden.
    private let updateModel: BrowserExtensionUpdateModel?

    init(
        space: BrowserSpace,
        extensionControllerPool: BrowserExtensionControllerPool
    ) {
        _model = State(
            initialValue: BrowserExtensionsModel(
                space: space,
                extensionControllerPool: extensionControllerPool
            )
        )
        platformActions = BrowserPlatformExtensionActions.make(
            extensionControllerPool: extensionControllerPool
        )
        updateModel = extensionControllerPool.updateModel
    }

    var body: some View {
        @Bindable var model = model

        Group {
            BrowserInstalledExtensionsSection(
                model: model,
                platformActions: platformActions
            )
            if let updateModel {
                BrowserExtensionUpdatesSection(model: updateModel)
            }
            BrowserPlatformExtensionAddSection(model: model)
        }
        .modifier(BrowserExtensionPackageImportModifier(model: model))
        .modifier(BrowserPlatformExtensionsViewSizingModifier())
        .alert(
            "Couldn’t Complete Extension Action",
            isPresented: Binding(
                get: { model.operationFailure != nil },
                set: { isPresented in
                    if !isPresented {
                        model.clearOperationFailure()
                    }
                }
            ),
            presenting: model.operationFailure
        ) { _ in
            Button("OK", action: model.clearOperationFailure)
        } message: { failure in
            Text(failure.message)
        }
        .confirmationDialog(
            "Remove Extension?",
            isPresented: Binding(
                get: { model.pendingRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        model.cancelRemoval()
                    }
                }
            ),
            presenting: model.pendingRemoval
        ) { extensionSummary in
            Button("Remove from \(model.space.name)", role: .destructive) {
                Task { await model.remove(extensionSummary) }
            }
            Button("Cancel", role: .cancel, action: model.cancelRemoval)
        } message: { extensionSummary in
            Text(
                "\(extensionSummary.displayName) and its Space-local data will be removed. The host app and other Spaces are unchanged."
            )
        }
    }
}

#Preview("Extensions") {
    Form {
        BrowserExtensionsView(
            space: BrowserExtensionsPreviewFixture.space,
            extensionControllerPool: BrowserExtensionsPreviewFixture.pool
        )
    }
    .frame(width: 620, height: 520)
}

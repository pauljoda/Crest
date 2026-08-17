import SwiftUI

struct BrowserPlatformExtensionAddSection: View {
    @State private var model: BrowserExtensionDiscoveryModel
    @State private var localPackageInstall: BrowserLocalExtensionInstallSession

    init(model: BrowserExtensionsModel) {
        _model = State(
            initialValue: BrowserExtensionDiscoveryModel(
                extensionsModel: model
            )
        )
        _localPackageInstall = State(
            initialValue: BrowserLocalExtensionInstallSession(
                space: model.space,
                extensionControllerPool: model.extensionControllerPool
            )
        )
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var localPackageInstall = localPackageInstall

        BrowserExtensionDiscoverySection(
            model: model,
            isPackageImportBusy: localPackageInstall.isBusy,
            choosePackage: localPackageInstall.choosePackage
        )
        .modifier(BrowserSafariExtensionImportModifier(model: model))
        .modifier(
            BrowserLocalExtensionImportModifier(
                session: localPackageInstall
            )
        )
        .sheet(isPresented: $localPackageInstall.isPresented) {
            BrowserLocalExtensionInstallView(
                session: localPackageInstall
            )
        }
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
    }
}

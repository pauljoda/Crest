import SwiftUI

struct BrowserPlatformExtensionAddSection: View {
    @State private var model: BrowserExtensionDiscoveryModel

    init(model: BrowserExtensionsModel) {
        _model = State(
            initialValue: BrowserExtensionDiscoveryModel(
                extensionsModel: model
            )
        )
    }

    var body: some View {
        @Bindable var model = model

        BrowserExtensionDiscoverySection(model: model)
            .modifier(BrowserSafariExtensionImportModifier(model: model))
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

#Preview("Add Mac Extension") {
    Form {
        BrowserPlatformExtensionAddSection(
            model: BrowserExtensionsPreviewFixture.model
        )
    }
    .frame(width: 620, height: 340)
}

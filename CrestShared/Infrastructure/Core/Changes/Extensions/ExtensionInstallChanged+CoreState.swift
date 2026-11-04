import Foundation

extension ExtensionInstallChanged {
    @MainActor func apply(to state: CoreState) {
        state.extensionInstalls[install.installID] = install
    }
}

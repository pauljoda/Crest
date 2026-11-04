import Foundation

extension InstalledExtensionsChanged {
    @MainActor func apply(to state: CoreState) {
        state.installedExtensions[engine, default: [:]][profileID] = extensions
    }
}

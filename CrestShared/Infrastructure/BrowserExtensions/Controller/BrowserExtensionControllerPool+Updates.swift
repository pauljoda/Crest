import Foundation

extension BrowserExtensionControllerPool {
    /// Every Chrome Web Store installation across every Space, as update
    /// targets.
    ///
    /// The registry is the source of truth for provenance: a row only appears
    /// here when it recorded a `chromeWebStore` source at install time, which
    /// is also the row that carries the verified extension identity and
    /// publisher-key hash a replacement must match.
    func chromeWebStoreUpdateTargets() -> [BrowserExtensionUpdateTarget] {
        persistenceController.installations.compactMap { installation in
            guard case .chromeWebStore(let source) = installation.source,
                source.extensionID.rawValue == installation.id
            else {
                return nil
            }
            return BrowserExtensionUpdateTarget(
                extensionID: installation.id,
                spaceID: installation.spaceID,
                displayName: installation.displayName,
                installedVersion: installation.version,
                isEnabled: installation.isEnabled
            )
        }
    }

    /// Arms the update cadence once launch restoration has settled.
    func startExtensionUpdatesIfNeeded() {
        updateModel?.scheduleCheckIfNeeded()
    }
}

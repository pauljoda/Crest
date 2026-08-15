/// An update applier with nothing to update and no way to install anything.
@MainActor
final class BrowserExtensionsPreviewUpdateApplier: BrowserExtensionUpdateApplying {
    func chromeWebStoreUpdateTargets() -> [BrowserExtensionUpdateTarget] {
        []
    }

    func applyUpdate(
        to target: BrowserExtensionUpdateTarget
    ) async throws -> String? {
        nil
    }
}

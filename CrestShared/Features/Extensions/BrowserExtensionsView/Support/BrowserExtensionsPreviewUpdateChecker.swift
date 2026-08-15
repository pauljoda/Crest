/// An update checker that answers "nothing newer" without a network.
///
/// Previews render the updates section against real model state, so the model
/// needs a checker; it must not be one that can reach the Chrome Web Store.
final class BrowserExtensionsPreviewUpdateChecker: BrowserExtensionUpdateChecking {
    func publishedVersion(
        forExtension extensionID: String
    ) async throws -> String? {
        nil
    }
}

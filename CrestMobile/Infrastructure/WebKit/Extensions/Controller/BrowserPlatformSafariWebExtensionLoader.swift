/// Browser extensions are a macOS-only feature for now.
///
/// This loader exists only so the shared `BrowserExtensionRuntimeContextController`
/// compiles for the mobile target. Mobile never instantiates the extension
/// runtime, so this is unreachable; it refuses rather than loading anything. Do
/// not grow this into a working adapter: mobile support needs a deliberate
/// product decision first, not a Safari app-extension loader here.
enum BrowserPlatformSafariWebExtensionLoader {
    static func load(
        _: BrowserSafariWebExtensionSource
    ) async throws -> BrowserSafariWebExtensionRuntimeResource {
        throw BrowserExtensionControllerPoolError
            .unsupportedInstallationSource
    }
}

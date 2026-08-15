import WebKit

/// Browser extensions are a macOS-only feature for now.
///
/// These members exist only so the shared `BrowserExtensionRuntimeContextController`
/// compiles for the mobile target. Extension commands bind keyboard shortcuts,
/// which iOS has no rebindable command table for, and mobile never instantiates
/// the extension runtime that would call them. Every body is deliberately empty.
/// Do not grow these into working adapters: mobile support needs a deliberate
/// product decision first, not shortcut capture here.
extension BrowserExtensionCommandController {
    func captureDefaults(
        for _: WKWebExtensionContext,
        extensionID _: String,
        spaceID _: SpaceID
    ) {}

    func applyStoredShortcuts(
        to _: WKWebExtensionContext,
        extensionID _: String,
        spaceID _: SpaceID
    ) {}

    func releaseContext(extensionID _: String, in _: SpaceID) {}
}

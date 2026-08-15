/// Browser extensions are a macOS-only feature for now.
///
/// This type exists only so the shared `BrowserExtensionsView` compiles for the
/// mobile target. Nothing on mobile presents that view, and mobile never builds
/// a `BrowserExtensionControllerPool`, so the pool handed in here is ignored and
/// no action is ever offered. Do not grow this into a working adapter: mobile
/// support needs a deliberate product decision first, not an implementation here.
enum BrowserPlatformExtensionActions {
    @MainActor
    static func make(
        extensionControllerPool _: BrowserExtensionControllerPool
    ) -> BrowserExtensionPlatformActions {
        .none
    }
}

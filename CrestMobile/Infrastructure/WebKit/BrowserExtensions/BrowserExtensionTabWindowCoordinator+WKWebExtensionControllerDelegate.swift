import WebKit

/// Browser extensions are a macOS-only feature for now.
///
/// This conformance exists only so the shared `BrowserExtensionTabWindowCoordinator`
/// compiles for the mobile target, where it assigns itself as a
/// `WKWebExtensionController` delegate. Every delegate method comes from the
/// shared default implementations; its dormant readiness forwarding adds no platform presentation
/// the macOS twin supplies, and mobile never instantiates the extension runtime
/// that would drive it. Do not grow this into a working adapter: mobile support
/// needs a deliberate product decision first, not popup or alert hosting here.
extension BrowserExtensionTabWindowCoordinator:
    WKWebExtensionControllerDelegate
{
    func prepareBackgroundForInitialContentScriptTraffic(
        _ context: WKWebExtensionContext
    ) async -> BrowserExtensionBackgroundWarmUp.Outcome {
        await BrowserExtensionBackgroundWarmUp(context: context).prepare()
    }
}

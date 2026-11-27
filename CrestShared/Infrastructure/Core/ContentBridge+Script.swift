import Foundation

extension ContentBridge {
    // MARK: - Actions - Script

    /// Returns this bridge's canonical JavaScript source from the portable
    /// core, including debug testing hooks when requested.
    nonisolated func script(includeTestingHooks: Bool = false) -> ContentBridgeScript {
        do {
            return try CrestCore.answer(
                ContentBridgeSource(bridge: self, includeTestingHooks: includeTestingHooks))
        } catch {
            preconditionFailure("The core could not serve the '\(name)' content bridge: \(error)")
        }
    }

    /// The bridge packaged as a `BrowserContentScript` for any engine running
    /// Crest's isolated content bridges.
    nonisolated func contentScript(includeTestingHooks: Bool = false) -> BrowserContentScript {
        let resolved = script(includeTestingHooks: includeTestingHooks)
        return BrowserContentScript(
            source: resolved.source,
            handlerName: resolved.handlerName,
            mainFrameOnly: resolved.mainFrameOnly
        )
    }
}

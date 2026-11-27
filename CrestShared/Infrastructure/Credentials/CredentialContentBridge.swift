import Foundation

/// The credential bridge every engine's pages run: its script and the name its
/// messages arrive under. The canonical JavaScript source lives in `CrestCore`
/// so every platform and engine runs the same form detection and fill bridge.
@MainActor
enum BrowserCredentialContentBridge {
    // MARK: - Static Variables

    static let messageHandlerName = ContentBridge.credentials.handlerName

    #if DEBUG
        static let source: String = ContentBridge.credentials.script(includeTestingHooks: true).source
    #else
        static let source: String = ContentBridge.credentials.script(includeTestingHooks: false).source
    #endif
}

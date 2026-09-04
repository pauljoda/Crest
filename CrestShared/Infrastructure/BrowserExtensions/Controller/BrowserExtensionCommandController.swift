import WebKit

@MainActor
final class BrowserExtensionCommandController {
    let persistence: BrowserExtensionPersistenceController
    var defaultsBySpace: [SpaceID: [String: [String: BrowserExtensionCommandShortcutOverride]]] = [:]
    var noteUserGesture: ((WKWebExtensionContext) -> Void)?
    var performSidebarCommand: ((WKWebExtensionContext, String) -> Bool)?

    init(persistence: BrowserExtensionPersistenceController) {
        self.persistence = persistence
    }
}

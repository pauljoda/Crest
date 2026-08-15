@MainActor
final class BrowserExtensionCommandController {
    let persistence: BrowserExtensionPersistenceController
    var defaultsBySpace: [SpaceID: [String: [String: BrowserExtensionCommandShortcutOverride]]] = [:]

    init(persistence: BrowserExtensionPersistenceController) {
        self.persistence = persistence
    }
}

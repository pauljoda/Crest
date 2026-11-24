import Foundation

extension ExportedCredential {
    /// A saved password as a Space's password file writes it, with its notes
    /// and code link, or for an HTTP authentication password without notes,
    /// a note naming how it is used.
    init(_ credential: BrowserCredential, extras: BrowserCredentialExtras? = nil) {
        let descriptor = credential.descriptor
        self.init(
            id: descriptor.id, origin: descriptor.origin, username: descriptor.username,
            displayName: descriptor.displayName, password: credential.password,
            note: extras?.notes.nilIfEmpty ?? descriptor.scope.settingsLabel ?? "",
            oneTimeCodeLink: extras?.codeLink)
    }
}

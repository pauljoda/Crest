import Foundation

/// What settings says about a Space's saved passwords, decided once.
///
/// Held apart from ``BrowserCredentialSpaceStore`` because none of it needs a
/// Keychain: it is the search predicate and the two sentences the shells had each
/// written their own drifting copy of, and pulling them out is what lets a test read
/// them without a vault.
enum BrowserCredentialSettingsPolicy {
    /// The four fields both shells searched: the account, the site, the label a
    /// reader gave it, and the authentication scope that narrows it.
    static func filter(
        _ descriptors: [CredentialDescriptor],
        matching query: String
    ) -> [CredentialDescriptor] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return descriptors }
        return descriptors.filter {
            $0.username.localizedCaseInsensitiveContains(query)
                || $0.origin.description.localizedCaseInsensitiveContains(query)
                || $0.displayName?.localizedCaseInsensitiveContains(query) == true
                || $0.scope.settingsLabel?.localizedCaseInsensitiveContains(query) == true
        }
    }

    /// Everything a reader needs before deleting: whose password, for which site,
    /// under which authentication scope, out of which Space — and whether the delete
    /// reaches past this device.
    static func deletionMessage(
        for descriptor: CredentialDescriptor,
        spaceName: String
    ) -> String {
        let synchronizationWarning =
            descriptor.isSynchronizable
            ? " This also removes synchronized copies from Crest’s iCloud Keychain item."
            : ""
        let scope = descriptor.scope.settingsLabel.map { " (\($0))" } ?? ""
        return
            "Delete \(descriptor.username)’s password for \(descriptor.origin.description)\(scope) from \(spaceName)?\(synchronizationWarning) This cannot be undone."
    }

    static func emptyDescription(isSearching: Bool) -> String {
        isSearching
            ? "Try another account name or site."
            : "Passwords offered after a successful sign-in will be stored only in this Space."
    }

    static let disabledDescription =
        "Crest Passwords is off in this Space. Saved passwords remain here until you delete them."
}

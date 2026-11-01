import Foundation

/// Imports another browser's saved passwords once its review is imported.
/// The core says which Spaces each password goes to, leaving out Spaces that
/// are gone or locked, and what each account means against the passwords a
/// Space already keeps; a Space keeps its saved password for an account it
/// already has. This writes each Space's Keychain inventory. A Space whose
/// passwords could not be read or written counts them as unsaved, apart from
/// the ones the review left out.
@MainActor
enum BrowserPasswordImportCommitter {
    // MARK: - Actions - Importing

    /// Imports `passwords` for the review setup holds over `browser`'s
    /// workspace, answering how many the Spaces took, how many none did, and
    /// how many could not be saved.
    static func commit(
        _ passwords: [BrowserImportedPassword],
        browser: BrowserStore
    ) async -> BrowserPasswordImportResult {
        guard !passwords.isEmpty else { return .empty }
        let routes: ImportPasswordRoutes
        do {
            routes = try browser.core.query(
                ImportPasswordDestinations(
                    workspaceID: browser.family.workspaceID, passwords: passwords.map(\.routingSource)))
        } catch {
            return BrowserPasswordImportResult(importedCount: 0, skippedCount: 0, unsavedCount: passwords.count)
        }
        var credentialsBySpace: [UUID: [ImportedCredential]] = [:]
        var skippedCount = 0
        for (index, (password, route)) in zip(passwords, routes.routes).enumerated() {
            guard !route.spaceIDs.isEmpty else {
                skippedCount += 1
                continue
            }
            for spaceID in route.spaceIDs {
                credentialsBySpace[spaceID, default: []].append(
                    ImportedCredential(
                        rowNumber: index + 2, displayName: password.origin.host, origin: password.origin,
                        username: password.username, password: password.password))
            }
        }

        var importedCount = 0
        var unsavedCount = 0
        for (spaceID, credentials) in credentialsBySpace {
            guard let space = browser.spaceModel(spaceID) else {
                skippedCount += credentials.count
                continue
            }
            do {
                let existing = try await browser.credentialInventory(in: spaceID)
                let plan = try browser.core.query(
                    PasswordImportPreview(credentials: credentials, existing: existing.map(ExistingCredential.init)))
                let review = BrowserCredentialImportReview(
                    plan: plan,
                    existingCredentials: existing,
                    destination: BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID),
                    synchronizesWithICloud: space.settings.credentialPreferences.syncsCrestPasswordsWithICloud
                )
                let resolution = try review.resolvedInventory()
                if resolution.summary.acceptedCount > 0 {
                    try await browser.replaceCredentialInventory(resolution.credentials, in: spaceID)
                }
                importedCount += resolution.summary.acceptedCount
                skippedCount += resolution.summary.skippedCount + resolution.summary.rejectedCount
            } catch {
                unsavedCount += credentials.count
            }
        }
        return BrowserPasswordImportResult(
            importedCount: importedCount, skippedCount: skippedCount, unsavedCount: unsavedCount)
    }
}

extension BrowserImportedPassword {
    /// Where the password belongs, as the core routes it: its profile and its
    /// site's host.
    var routingSource: ImportPasswordSource {
        ImportPasswordSource(profileName: sourceProfileName, host: origin.host)
    }
}

extension BrowserPasswordImportCandidate {
    /// Where the password belongs, as the core counts it for the review.
    var routingSource: ImportPasswordSource {
        ImportPasswordSource(profileName: sourceProfileName, host: origin.host)
    }
}

import SwiftUI

/// The Space-scoped credential work both shells were doing twice.
///
/// Reading a Space's Keychain descriptors, deleting one, turning iCloud
/// synchronization on, and authenticating an export are four operations with four
/// loading flags and five error sentences, and all of it had been written out once in
/// ``BrowserPasswordSettingsPane``'s ancestors on each platform. The sentences differ
/// only where the platform differs — nowhere, as it turned out, which is why the
/// copies had already drifted into "removes synchronized copies *from*" against
/// "*of*" Crest's Keychain item.
@Observable
@MainActor
final class BrowserCredentialSpaceStore {
    private(set) var descriptors: [CredentialDescriptor] = []
    /// What each login keeps beside its password, as the list says it.
    private(set) var extras: [UUID: BrowserCredentialExtrasSummary] = [:]
    /// What the core found wrong with each login's password: reused, weak or
    /// saved for a site without HTTPS. Worked out afresh on each load.
    private(set) var health: [UUID: CredentialHealth] = [:]
    /// The notes of the logins that keep some, read so a search finds them.
    /// They never show here; the editor shows them after authentication.
    @ObservationIgnored private var notes: [UUID: String] = [:]
    /// How many of the Space's saved passwords no longer read back, which
    /// `descriptors` leaves out.
    private(set) var unreadableCount = 0
    private(set) var isLoading = false
    private(set) var isChangingSynchronization = false
    private(set) var isPreparingExport = false
    private(set) var isPreparingImport = false
    private(set) var isCommittingImport = false
    private(set) var isDeletingSelection = false
    /// Which rows are mid-delete, so a row can show its own progress rather than
    /// blanking the whole list.
    private(set) var deletingCredentialIDs: Set<UUID> = []
    var errorMessage: String?
    var exportDocument: BrowserCredentialCSVDocument?
    var exportFilename = "Crest Passwords.csv"
    var importReview: BrowserCredentialImportReview?

    @ObservationIgnored private let browser: BrowserStore

    /// The Spaces whose stored spellings this launch already mended.
    private static var respelledSpaces: Set<UUID> = []

    init(browser: BrowserStore) {
        self.browser = browser
    }

    /// The descriptors that match a query, over the fields both shells
    /// searched and the logins' notes.
    func descriptors(matching query: String) -> [CredentialDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = Set(descriptors.matching(query).map(\.id))
        return descriptors.filter {
            matches.contains($0.id)
                || !trimmed.isEmpty && notes[$0.id]?.localizedCaseInsensitiveContains(trimmed) == true
                || !trimmed.isEmpty && $0.sites.contains { $0.description.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    func isDeleting(_ descriptor: CredentialDescriptor) -> Bool {
        deletingCredentialIDs.contains(descriptor.id)
    }

    func load(
        in spaceID: UUID?,
        accessController: BrowserSpaceAccessController
    ) async {
        guard let spaceID,
            unlockedSpace(spaceID, accessController: accessController) != nil
        else {
            clearSensitiveData()
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Old spellings of IP addresses are mended once per launch.
            if Self.respelledSpaces.insert(spaceID).inserted {
                _ = try? await browser.respellCredentials(in: spaceID)
            }
            let inventory = try await browser.savedCredentialInventory(in: spaceID)
            guard !Task.isCancelled,
                unlockedSpace(spaceID, accessController: accessController) != nil
            else {
                clearSensitiveData()
                return
            }
            descriptors = inventory.descriptors
            unreadableCount = inventory.unreadableCount
            extras = inventory.extras
            await readNotes(in: spaceID, accessController: accessController)
            await checkHealth(in: spaceID, accessController: accessController)
        } catch {
            guard !Task.isCancelled,
                unlockedSpace(spaceID, accessController: accessController) != nil
            else {
                clearSensitiveData()
                return
            }
            descriptors = []
            unreadableCount = 0
            errorMessage = "Crest couldn’t read this Space’s saved-password metadata."
        }
    }

    /// Reads the notes of the logins that keep some, for search.
    private func readNotes(in spaceID: UUID, accessController: BrowserSpaceAccessController) async {
        var read: [UUID: String] = [:]
        for (id, summary) in extras where summary.hasNotes {
            if let extras = try? await browser.credentialExtras(id: id, in: spaceID), !extras.notes.isEmpty {
                read[id] = extras.notes
            }
        }
        guard !Task.isCancelled, unlockedSpace(spaceID, accessController: accessController) != nil else { return }
        notes = read
    }

    /// Has the core check the Space's passwords. They cross only for the
    /// question; the answer names none.
    private func checkHealth(in spaceID: UUID, accessController: BrowserSpaceAccessController) async {
        var checked: [CheckedCredential] = []
        for descriptor in descriptors where descriptor.scope == .webForm {
            guard let credential = try? await browser.credential(id: descriptor.id, in: spaceID) else { continue }
            checked.append(
                CheckedCredential(
                    id: descriptor.id, origin: descriptor.origin, username: descriptor.username,
                    password: credential.password))
        }
        let report = try? browser.core.query(PasswordHealth(credentials: checked))
        // A list cleared or reloaded meanwhile keeps its own answer.
        guard !Task.isCancelled, unlockedSpace(spaceID, accessController: accessController) != nil,
            Set(descriptors.map(\.id)).isSuperset(of: checked.map(\.id))
        else { return }
        health = Dictionary((report?.credentials ?? []).map { ($0.id, $0) }) { first, _ in first }
    }

    /// How many logins have each concern, in the core's order.
    var concernCounts: [(concern: PasswordConcern, count: Int)] {
        PasswordConcern.all.compactMap { concern in
            let count = health.values.count { $0.concerns.contains(concern) }
            return count > 0 ? (concern, count) : nil
        }
    }

    func clearSensitiveData() {
        descriptors = []
        health = [:]
        extras = [:]
        notes = [:]
        unreadableCount = 0
        deletingCredentialIDs = []
        errorMessage = nil
        exportDocument = nil
        importReview = nil
    }

    func delete(
        _ descriptor: CredentialDescriptor,
        reloading spaceID: UUID?,
        accessController: BrowserSpaceAccessController
    ) {
        guard unlockedSpace(descriptor.spaceID, accessController: accessController) != nil else { return }
        deletingCredentialIDs.insert(descriptor.id)
        errorMessage = nil
        Task { @MainActor in
            defer { deletingCredentialIDs.remove(descriptor.id) }
            do {
                try await browser.deleteCredential(
                    id: descriptor.id,
                    in: descriptor.spaceID
                )
                await load(in: spaceID, accessController: accessController)
            } catch {
                errorMessage = "Crest couldn’t delete that password from this Space."
            }
        }
    }

    /// Removes the Space's saved passwords that no longer read back, which no
    /// list shows and no page is offered.
    func deleteUnreadable(
        in spaceID: UUID,
        accessController: BrowserSpaceAccessController
    ) {
        guard unlockedSpace(spaceID, accessController: accessController) != nil else { return }
        errorMessage = nil
        Task { @MainActor in
            do {
                try await browser.deleteUnreadableCredentials(in: spaceID)
                await load(in: spaceID, accessController: accessController)
            } catch {
                errorMessage = String(localized: "Crest couldn’t remove the passwords it can’t read.")
            }
        }
    }

    /// Turning synchronization on or off rewrites the Space's existing Keychain
    /// items, so it is an operation with a progress state and a failure — which is
    /// why it is here rather than among the plain preference bindings.
    func setSynchronization(
        _ enabled: Bool,
        in spaceID: UUID,
        accessController: BrowserSpaceAccessController
    ) {
        guard unlockedSpace(spaceID, accessController: accessController) != nil else { return }
        isChangingSynchronization = true
        errorMessage = nil
        Task { @MainActor in
            defer { isChangingSynchronization = false }
            do {
                try await browser.setCrestPasswordSynchronization(enabled, in: spaceID)
                await load(in: spaceID, accessController: accessController)
            } catch {
                errorMessage = "Crest couldn’t update iCloud synchronization."
            }
        }
    }

    func synchronizationBinding(
        in space: SpaceModel,
        accessController: BrowserSpaceAccessController
    ) -> Binding<Bool> {
        Binding {
            space.settings.credentialPreferences.syncsCrestPasswordsWithICloud
        } set: { [weak self] enabled in
            self?.setSynchronization(
                enabled,
                in: space.id,
                accessController: accessController
            )
        }
    }

    /// Authenticates, builds the CSV, and reports whether the exporter should open.
    /// The Space is re-checked afterwards because authentication can outlive the
    /// reader's interest in that Space.
    func prepareExport(
        in spaceID: UUID,
        only ids: Set<UUID>? = nil,
        accessController: BrowserSpaceAccessController,
        isStillSelected: () -> Bool
    ) async -> Bool {
        guard unlockedSpace(spaceID, accessController: accessController) != nil else { return false }
        isPreparingExport = true
        errorMessage = nil
        defer { isPreparingExport = false }
        do {
            let export = try await BrowserCredentialSensitiveAccess(browser: browser)
                .exportCredentials(in: spaceID, only: ids)
            guard isStillSelected(),
                unlockedSpace(spaceID, accessController: accessController) != nil
            else { return false }
            exportDocument = BrowserCredentialCSVDocument(data: export.contents)
            exportFilename = export.fileName
            return true
        } catch {
            errorMessage = "Crest couldn’t authenticate and export this Space’s passwords."
            return false
        }
    }

    func reportExportFailure() {
        errorMessage = "Crest couldn’t export those passwords."
    }

    func prepareImport(
        from url: URL,
        in spaceID: UUID,
        accessController: BrowserSpaceAccessController,
        isStillSelected: () -> Bool
    ) async {
        guard let space = unlockedSpace(spaceID, accessController: accessController),
            space.settings.credentialPreferences.isEnabled
        else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        isPreparingImport = true
        errorMessage = nil
        importReview = nil
        defer { isPreparingImport = false }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }

        // The Space's passwords are read first, so a failure there is never
        // blamed on the file. Declining to authenticate says nothing.
        let existing: [BrowserCredential]
        do {
            existing = try await BrowserCredentialSensitiveAccess(browser: browser)
                .credentialInventory(
                    matching: assignment,
                    reason: String(
                        localized: "Authenticate to import passwords into \(space.settings.name)."
                    )
                )
        } catch BrowserCredentialSensitiveAccessError.authenticationDenied {
            return
        } catch {
            errorMessage = String(localized: "Crest couldn’t read this Space’s passwords.")
            return
        }
        guard isStillSelected(), browser.spaceModel(matching: assignment) != nil else { return }
        var existingExtras: [UUID: BrowserCredentialExtras] = [:]
        for credential in existing {
            existingExtras[credential.descriptor.id] = try? await browser.credentialExtras(
                id: credential.descriptor.id, in: spaceID)
        }
        do {
            let plan = try await Self.plan(
                importing: try Self.document(at: url), against: existing, extras: existingExtras, core: browser.core)
            guard isStillSelected(),
                let currentSpace = browser.spaceModel(matching: assignment)
            else { return }
            importReview = BrowserCredentialImportReview(
                plan: plan,
                existingCredentials: existing,
                destination: assignment,
                synchronizesWithICloud: currentSpace.settings.credentialPreferences.syncsCrestPasswordsWithICloud
            )
        } catch let rejection as Rejection {
            if let invalid = rejection.invalidCredentialFile {
                errorMessage = String(localized: invalid.flaw.message)
            } else {
                errorMessage = rejection.explanation
            }
        } catch {
            errorMessage = String(localized: "Crest couldn’t read that password file.")
        }
    }

    /// The file at `url`, read no further than one byte past the largest
    /// password file the core imports, so a larger one is refused as such
    /// without reading it whole.
    private static func document(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: CapacityLimits.current.credentialFileBytes + 1) ?? Data()
    }

    /// The core's plan for importing `document` against `existing`, read away
    /// from the main thread.
    private static func plan(
        importing document: Data,
        against existing: [BrowserCredential],
        extras: [UUID: BrowserCredentialExtras],
        core: CrestCore
    ) async throws -> CredentialImportPlan {
        let query = CredentialImportPreview(
            document: document,
            existing: existing.map { ExistingCredential($0, extras: extras[$0.descriptor.id]) })
        return try await Task.detached(priority: .userInitiated) { try core.query(query) }.value
    }

    func selectImport(
        _ selection: BrowserCredentialImportSelection,
        for id: BrowserCredentialImportGroupID
    ) {
        importReview?.select(selection, for: id)
    }

    func cancelImport() {
        importReview = nil
    }

    func commitImport(
        accessController: BrowserSpaceAccessController,
        isStillSelected: () -> Bool
    ) async {
        guard let plan = importReview,
            let space = browser.spaceModel(matching: plan.destination),
            !accessController.isLocked(space),
            isStillSelected()
        else { return }
        isCommittingImport = true
        errorMessage = nil
        defer { isCommittingImport = false }
        // Each step says what it left: nothing before the write, the Space's
        // passwords as they were when the write is undone, and the import
        // itself once the write succeeds. Declining to authenticate says nothing.
        let currentInventory: [BrowserCredential]
        do {
            currentInventory = try await BrowserCredentialSensitiveAccess(browser: browser)
                .credentialInventory(
                    matching: plan.destination,
                    reason: String(
                        localized: "Authenticate to commit the password import into \(space.settings.name)."
                    )
                )
        } catch BrowserCredentialSensitiveAccessError.authenticationDenied {
            return
        } catch {
            errorMessage = String(localized: "Crest couldn’t read this Space’s passwords. Nothing was imported.")
            return
        }
        guard plan.matchesExistingInventory(currentInventory) else {
            errorMessage = String(
                localized:
                    "This Space’s saved passwords changed during review. No passwords were imported; choose the file again to refresh conflicts."
            )
            importReview = nil
            return
        }
        guard isStillSelected(), browser.spaceModel(matching: plan.destination) != nil else { return }
        let resolution: BrowserCredentialImportResolution
        do {
            resolution = try plan.resolvedInventory()
            if resolution.summary.acceptedCount > 0 {
                try await browser.replaceCredentialInventory(
                    resolution.credentials,
                    in: plan.destination.spaceID
                )
            }
        } catch CredentialVaultError.atomicReplacementRestoreFailed {
            errorMessage = String(
                localized:
                    "Crest couldn’t finish the import or restore the original Keychain inventory. Review this Space before trying again."
            )
            return
        } catch {
            errorMessage = String(
                localized: "Crest couldn’t import these passwords. This Space’s passwords are unchanged.")
            return
        }
        // Notes and code links the file brought go beside the passwords now
        // written, keeping what a login kept where the file brought nothing.
        for (id, details) in resolution.details {
            let saved = try? await browser.credentialExtras(id: id, in: plan.destination.spaceID)
            try? await browser.saveCredentialExtras(
                details.merged(into: saved), forCredential: id, in: plan.destination.spaceID)
        }
        importReview = nil
        // The import is done; a Space chosen meanwhile shows its own passwords.
        guard isStillSelected(), browser.spaceModel(matching: plan.destination) != nil else { return }
        BrowserNoticeCenter.shared.post(resolution.summary.notice)
        await load(
            in: plan.destination.spaceID,
            accessController: accessController
        )
    }

    /// Authenticates and deletes the selected logins one by one, each with
    /// its notes and code, leaving every other login as it was.
    func deleteSelection(
        _ ids: Set<UUID>,
        in spaceID: UUID,
        accessController: BrowserSpaceAccessController,
        isStillSelected: () -> Bool
    ) async -> Bool {
        guard !ids.isEmpty,
            let space = unlockedSpace(spaceID, accessController: accessController)
        else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        isDeletingSelection = true
        errorMessage = nil
        defer { isDeletingSelection = false }
        do {
            guard
                try await BrowserCredentialSensitiveAccess(browser: browser).authenticate(
                    reason: String(localized: "Authenticate to delete selected passwords from \(space.settings.name)."))
            else { return false }
            guard isStillSelected(), browser.spaceModel(matching: assignment) != nil else { return false }
            for id in ids {
                try await browser.deleteCredential(id: id, in: spaceID)
            }
            await load(in: spaceID, accessController: accessController)
            return true
        } catch {
            errorMessage = String(localized: "Crest couldn’t delete every selected password.")
            await load(in: spaceID, accessController: accessController)
            return false
        }
    }

    /// Authenticates and moves the selected logins into another Space.
    func move(
        _ ids: Set<UUID>,
        from spaceID: UUID,
        to destination: UUID,
        accessController: BrowserSpaceAccessController
    ) async -> Bool {
        guard !ids.isEmpty, let space = unlockedSpace(spaceID, accessController: accessController),
            let target = unlockedSpace(destination, accessController: accessController)
        else { return false }
        isDeletingSelection = true
        errorMessage = nil
        defer { isDeletingSelection = false }
        do {
            guard
                try await BrowserCredentialSensitiveAccess(browser: browser).authenticate(
                    reason: String(
                        localized:
                            "Authenticate to move passwords from \(space.settings.name) to \(target.settings.name)."))
            else { return false }
            try await browser.moveCredentials(Array(ids), from: spaceID, to: destination)
            await load(in: spaceID, accessController: accessController)
            BrowserNoticeCenter.shared.post(.passwordsMoved(count: ids.count, to: target.settings.name))
            return true
        } catch {
            errorMessage = String(localized: "Crest couldn’t move every selected password.")
            await load(in: spaceID, accessController: accessController)
            return false
        }
    }

    func deletionMessage(
        for descriptor: CredentialDescriptor,
        in space: SpaceModel?
    ) -> String {
        descriptor.deletionMessage(
            spaceName: space?.settings.name
                ?? browser.spaceModel(descriptor.spaceID)?.settings.name
                ?? "this Space"
        )
    }

    /// The Space of the read model the store may reveal and change, while
    /// this process holds it unlocked.
    private func unlockedSpace(
        _ spaceID: UUID,
        accessController: BrowserSpaceAccessController
    ) -> SpaceModel? {
        guard let space = browser.spaceModel(spaceID), !accessController.isLocked(space) else { return nil }
        return space
    }
}

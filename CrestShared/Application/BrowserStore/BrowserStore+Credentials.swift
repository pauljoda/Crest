import Foundation

// MARK: - Suggestion Loading

extension BrowserStore {
    func credentialSuggestions(
        for origin: CredentialOrigin,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        guard let url = URL(string: origin.description) else {
            throw CredentialVaultError.invalidOrigin
        }
        return try await credentialSuggestions(for: url, in: spaceID)
    }
}

// MARK: - Lookup

extension BrowserStore {
    func credentialSuggestions(for url: URL) async throws -> [CredentialDescriptor] {
        try await credentialSuggestions(for: url, in: try requireShownSpaceID())
    }

    /// The passwords the Space's group keeps: the ones its primary keeps for
    /// the group and the ones each Sub-Space saved before it joined.
    func savedCredentialDescriptors(in spaceID: UUID) async throws -> [CredentialDescriptor] {
        _ = try requireSpace(spaceID)
        return try await groupDescriptors(of: spaceID) { try await credentialVault.descriptors(in: $0) }
    }

    /// The passwords the Space's group keeps, with how many more no longer
    /// read back, which every list and suggestion leaves out: one read of
    /// each vault.
    func savedCredentialInventory(in spaceID: UUID) async throws -> CredentialInventory {
        _ = try requireSpace(spaceID)
        var descriptors: [CredentialDescriptor] = []
        var unreadableCount = 0
        var extras: [UUID: BrowserCredentialExtrasSummary] = [:]
        for vault in credentialSpaceIDs(of: spaceID) {
            let inventory = try await credentialVault.inventory(in: vault)
            descriptors += inventory.descriptors
            unreadableCount += inventory.unreadableCount
            extras.merge(inventory.extras) { kept, _ in kept }
        }
        return CredentialInventory(descriptors: descriptors, unreadableCount: unreadableCount, extras: extras)
    }

    /// The notes and code the login `id` keeps, from whichever vault of the
    /// Space's group keeps it, or nil when it keeps none.
    func credentialExtras(id: UUID, in spaceID: UUID) async throws -> BrowserCredentialExtras? {
        _ = try requireSpace(spaceID)
        for vault in credentialSpaceIDs(of: spaceID) {
            if let extras = try await credentialVault.extras(id: id, in: vault) { return extras }
        }
        return nil
    }

    func credentialSuggestions(
        for url: URL,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        _ = try requireSpace(spaceID)
        let origin = CredentialOrigin(url: url)
        guard try credentialAccess(.fill, in: spaceID, origin: origin).refusal == nil else { return [] }
        guard let origin else {
            throw CredentialVaultError.invalidOrigin
        }
        return try await groupDescriptors(of: spaceID) {
            try await credentialVault.descriptors(matching: origin, in: $0)
        }
    }

    func credential(id: UUID) async throws -> BrowserCredential? {
        try await credential(id: id, in: try requireShownSpaceID())
    }

    /// The password `id` names among the ones the Space's group keeps.
    func credential(id: UUID, in spaceID: UUID) async throws -> BrowserCredential? {
        _ = try requireSpace(spaceID)
        for vault in credentialSpaceIDs(of: spaceID) {
            if let credential = try await credentialVault.credential(id: id, in: vault) { return credential }
        }
        return nil
    }

    func credentialInventory(in spaceID: UUID) async throws -> [BrowserCredential] {
        _ = try requireSpace(spaceID)
        let descriptors = try await credentialVault.descriptors(in: spaceID)
        var credentials: [BrowserCredential] = []
        credentials.reserveCapacity(descriptors.count)
        for descriptor in descriptors {
            guard
                let credential = try await credentialVault.credential(
                    id: descriptor.id,
                    in: spaceID
                ),
                credential.descriptor == descriptor,
                credential.descriptor.spaceID == spaceID
            else {
                throw BrowserCredentialSensitiveAccessError.malformedCredentialInventory
            }
            credentials.append(credential)
        }
        return credentials
    }

    func httpAuthenticationCredential(
        for protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) async throws -> BrowserCredential? {
        _ = try requireSpace(spaceID)
        guard try credentialAccess(.fill, in: spaceID, origin: protectionSpace.origin).refusal == nil else {
            return nil
        }
        let descriptors = try await groupDescriptors(of: spaceID) {
            try await credentialVault.descriptors(matching: protectionSpace, in: $0)
        }
        // Without a recency answer from the core, nothing is filled.
        guard let descriptor = try? core.mostRecentCredential(descriptors) else {
            return nil
        }
        return try await credentialVault.credential(id: descriptor.id, in: descriptor.spaceID)
    }

    // MARK: - Actions - Groups

    private func requireSpace(_ spaceID: UUID) throws -> SpaceModel {
        guard let space = spaceModel(spaceID) else { throw CredentialVaultError.missingSpace }
        return space
    }

    private func requireShownSpaceID() throws -> UUID {
        guard let spaceID = shownSpace?.id else { throw CredentialVaultError.missingSpace }
        return spaceID
    }

    /// What `read` answers for each vault of the group of `spaceID`, the
    /// primary's first.
    /// Whether the passwords of `spaceID` serve `use`, for a page of `origin`
    /// when one is named, and the Spaces whose vaults hold them, as the core
    /// answers. Throws `missingSpace` for a Space the core does not know.
    func credentialAccess(
        _ use: CredentialUse, in spaceID: UUID, origin: CredentialOrigin? = nil
    ) throws(CredentialVaultError) -> CredentialAccessAnswer {
        do {
            return try core.query(
                CredentialAccess(workspaceID: family.workspaceID, spaceID: spaceID, use: use, origin: origin))
        } catch {
            throw .missingSpace
        }
    }

    private func groupDescriptors(
        of spaceID: UUID, _ read: (UUID) async throws -> [CredentialDescriptor]
    ) async throws -> [CredentialDescriptor] {
        var descriptors: [CredentialDescriptor] = []
        for vault in credentialSpaceIDs(of: spaceID) { descriptors += try await read(vault) }
        return descriptors
    }

    /// The vault of the group of `spaceID` that keeps `existing`, or the one
    /// that keeps the group's new passwords. Throws when `existing` belongs to
    /// another group.
    private func credentialVaultID(of spaceID: UUID, keeping existing: CredentialDescriptor?) throws -> UUID {
        let vaults = credentialSpaceIDs(of: spaceID)
        guard let existing else { return vaults[0] }
        guard vaults.contains(existing.spaceID) else {
            throw CredentialVaultError.spaceMismatch(expected: vaults[0], actual: existing.spaceID)
        }
        return existing.spaceID
    }
}

// MARK: - Generated passwords and system Passwords

extension BrowserStore {
    /// How to compose a generated password in `style` that meets
    /// `requirements`, the limits of the field it is for. The password itself
    /// is drawn natively, so it never enters the core.
    func strongPasswordRecipe(
        for requirements: PasswordRequirements = .none, style: PasswordStyle = .grouped
    ) throws -> StrongPasswordRecipe {
        do {
            return try core.query(StrongPassword(requirements: requirements, style: style))
        } catch {
            throw BrowserStrongPasswordGenerationError.unavailable
        }
    }

    /// Whether this launch can offer saved passwords to the system's Passwords
    /// app. A core that refuses the platform's facts reports it unsupported.
    var systemPasswordWriteThroughAvailability: SystemPasswordWriteThroughAvailability {
        (try? core.query(BrowserSystemPasswordWriteThroughSystem.facts()))?.availability ?? .unsupportedPlatform
    }

    /// Whether a save prompt in a Space with these preferences goes on to
    /// offer the password to the system's Passwords app. A core that cannot
    /// answer does not offer it.
    func offersSystemPasswordWriteThrough(for preferences: CredentialPreferences) -> Bool {
        let offer = SystemPasswordOffer(
            spaceOffersSystemPasswords: preferences.alsoOffersSaveToSystemPasswords,
            availability: systemPasswordWriteThroughAvailability, isPrivateBrowsing: isPrivateBrowsing)
        return (try? core.query(offer))?.offers ?? false
    }
}

// MARK: - Preferences

extension BrowserStore {
    /// Stops the Space offering to save passwords for `site`. Saving one on
    /// purpose, and filling, still work there.
    func neverSaveCredentials(for site: CredentialOrigin, in spaceID: UUID) {
        guard var preferences = spaceModel(spaceID)?.settings.credentialPreferences,
            !preferences.neverSavedSites.contains(site)
        else { return }
        preferences.neverSavedSites.append(site)
        updateCredentialPreferences(preferences, in: spaceID)
    }

    /// Lets the Space offer to save passwords for `site` again.
    func allowSavingCredentials(for site: CredentialOrigin, in spaceID: UUID) {
        guard var preferences = spaceModel(spaceID)?.settings.credentialPreferences,
            preferences.neverSavedSites.contains(site)
        else { return }
        preferences.neverSavedSites.removeAll { $0 == site }
        updateCredentialPreferences(preferences, in: spaceID)
    }

    /// Whether the Space offers to save a password a page at `origin` sent:
    /// not in a private window, with its manager off, on a page without
    /// HTTPS, or on a site the person asked never to save for.
    func offersToSaveCredentials(for origin: CredentialOrigin, in spaceID: UUID) -> Bool {
        (try? credentialAccess(.offerSave, in: spaceID, origin: origin))?.refusal == nil
    }

    func updateCredentialPreferences(
        _ preferences: CredentialPreferences,
        in spaceID: UUID
    ) {
        sendSpaceSettings(
            SetCredentialPreferences(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID, preferences: preferences))
    }

    func setCrestPasswordSynchronization(
        _ isSynchronizable: Bool,
        in spaceID: UUID
    ) async throws {
        // The vault write and its preference belong to the store that owns
        // the Space's credential settings, which may be a borrowed source.
        let owner = profileSettingsBrowser
        guard owner === self else {
            try await owner.setCrestPasswordSynchronization(isSynchronizable, in: spaceID)
            return
        }
        let space = try requireSpace(spaceID)
        guard space.settings.credentialPreferences.syncsCrestPasswordsWithICloud != isSynchronizable else {
            return
        }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)

        for vault in credentialSpaceIDs(of: spaceID) {
            try await credentialVault.setSynchronizable(isSynchronizable, in: vault)
        }
        guard let current = spaceModel(matching: assignment)?.settings.credentialPreferences else {
            throw CredentialVaultError.missingSpace
        }
        let preferences = CredentialPreferences(
            isEnabled: current.isEnabled, syncsCrestPasswordsWithICloud: isSynchronizable,
            alsoOffersSaveToSystemPasswords: current.alsoOffersSaveToSystemPasswords,
            neverSavedSites: current.neverSavedSites)
        // The native credential operation completed for this profile. Persist
        // its corresponding policy through the same session authority.
        let sent = SetCredentialPreferences(workspaceID: family.workspaceID, spaceID: spaceID, preferences: preferences)
        if !family.send(sent, from: self),
            spaceModel(spaceID)?.settings.credentialPreferences != preferences
        {
            throw CredentialVaultError.preferenceUpdateFailed
        }
    }

}

// MARK: - Saving

extension BrowserStore {
    /// The core matches the account and plans the save from descriptors
    /// alone. The stored password is compared here and only the answer is
    /// passed on. A core that cannot answer fails the plan: nothing is saved.
    func credentialSavePlan(
        for candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        now: Date = .now
    ) async throws -> any BrowserCredentialSavePlan {
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        let descriptors = try await groupDescriptors(of: spaceID) {
            try await credentialVault.descriptors(matching: candidate.origin, in: $0)
        }
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        // A password change found its saved login by the current password,
        // and updates that one even when others share its username.
        let descriptor: CredentialDescriptor?
        if let accountID = candidate.accountID {
            guard let account = descriptors.first(where: { $0.id == accountID }) else {
                throw CredentialVaultError.saveDecisionUnavailable
            }
            descriptor = account
        } else if candidate.username.isEmpty {
            // A password made before the form names its account matches none.
            descriptor = nil
        } else {
            do {
                descriptor = try core.credentialSaveMatch(username: candidate.username, in: descriptors)
            } catch {
                throw CredentialVaultError.saveDecisionUnavailable
            }
        }
        var storedPasswordMatches: Bool?
        if let descriptor {
            let credential = try await credentialVault.credential(
                id: descriptor.id,
                in: descriptor.spaceID
            )
            try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
            storedPasswordMatches = credential.map { $0.password == candidate.password }
        }
        let stored = descriptor.flatMap { descriptor in
            storedPasswordMatches.map {
                CredentialStoredComparison(id: descriptor.id, passwordMatches: $0)
            }
        }
        guard let plan = try? core.query(CredentialSave(matchID: descriptor?.id, stored: stored)),
            plan.kind == .create || plan.id == descriptor?.id
        else { throw CredentialVaultError.saveDecisionUnavailable }
        switch (plan.kind, descriptor) {
        case (.create, _): return BrowserCredentialCreatePlan()
        case (.update, let descriptor?): return BrowserCredentialUpdatePlan(existing: descriptor)
        case (.alreadyStored, let descriptor?): return BrowserCredentialAlreadyStoredPlan(existing: descriptor)
        default: throw CredentialVaultError.saveDecisionUnavailable
        }
    }

    /// The saved login, among those the Space keeps for the candidate's site,
    /// whose password is the candidate's current password: the most recent
    /// when several are. Nil when none is, or the candidate has no current
    /// password. The passwords are compared here; the core only chooses among
    /// the logins that match.
    func accountHoldingCurrentPassword(
        of candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID
    ) async throws -> CredentialDescriptor? {
        guard let currentPassword = candidate.currentPassword else { return nil }
        let descriptors = try await groupDescriptors(of: spaceID) {
            try await credentialVault.descriptors(matching: candidate.origin, in: $0)
        }
        var holding: [CredentialDescriptor] = []
        for descriptor in descriptors {
            let credential = try await credentialVault.credential(id: descriptor.id, in: descriptor.spaceID)
            if credential?.password == currentPassword { holding.append(descriptor) }
        }
        return try core.mostRecentCredential(holding)
    }

    func commitCredentialSave(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        now: Date = .now
    ) async throws -> BrowserCredentialSaveResult {
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        let key = BrowserCredentialSaveKey(candidate: candidate, spaceID: spaceID)
        let precedingCompletion = credentialSaveOperations[key]?.completion
        let operationID = UUID()
        let task = Task { @MainActor [self] in
            if let precedingCompletion {
                await precedingCompletion.value
            }
            return try await performCredentialSave(
                candidate,
                in: spaceID,
                now: now
            )
        }
        let completion = Task {
            _ = try? await task.value
        }
        credentialSaveOperations[key] = BrowserCredentialSaveOperation(
            id: operationID,
            completion: completion
        )
        defer {
            if credentialSaveOperations[key]?.id == operationID {
                credentialSaveOperations[key] = nil
            }
        }
        return try await task.value
    }

    @discardableResult
    func saveCredential(
        username: String,
        password: String,
        for url: URL,
        displayName: String? = nil,
        isSynchronizable: Bool? = nil,
        now: Date = Date()
    ) async throws -> CredentialDescriptor {
        try await saveCredential(
            username: username,
            password: password,
            for: url,
            in: try requireShownSpaceID(),
            displayName: displayName,
            replacing: nil,
            isSynchronizable: isSynchronizable,
            now: now
        )
    }

    @discardableResult
    func saveCredential(
        username: String,
        password: String,
        for url: URL,
        in spaceID: UUID,
        displayName: String? = nil,
        replacing existing: CredentialDescriptor? = nil,
        isSynchronizable: Bool? = nil,
        now: Date = Date()
    ) async throws -> CredentialDescriptor {
        let space = try requireSpace(spaceID)
        let origin = CredentialOrigin(url: url)
        if let refusal = try credentialAccess(.save, in: spaceID, origin: origin).refusal {
            throw CredentialVaultError(refusal)
        }
        let resolvedSynchronization =
            isSynchronizable
            ?? space.settings.credentialPreferences.syncsCrestPasswordsWithICloud
        guard let origin else {
            throw CredentialVaultError.invalidOrigin
        }

        // A group keeps new passwords in its primary, and each one where it is.
        let vaultID = try credentialVaultID(of: spaceID, keeping: existing)
        let descriptor: CredentialDescriptor
        if var existing {
            guard existing.origins.contains(origin) else {
                throw CredentialVaultError.invalidOrigin
            }
            existing.username = username
            existing.displayName = displayName?.nilIfEmpty ?? existing.displayName
            existing.updatedAt = now
            existing.passwordChangedAt = now
            existing.isSynchronizable = resolvedSynchronization
            descriptor = existing
        } else {
            descriptor = CredentialDescriptor(
                spaceID: vaultID,
                origin: origin,
                username: username,
                displayName: displayName?.nilIfEmpty,
                createdAt: now,
                isSynchronizable: resolvedSynchronization
            )
        }
        try await credentialVault.save(
            BrowserCredential(descriptor: descriptor, password: password),
            in: vaultID
        )
        return descriptor
    }

    @discardableResult
    func saveHTTPAuthenticationCredential(
        username: String,
        password: String,
        protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID,
        replacing existing: CredentialDescriptor? = nil,
        now: Date = Date()
    ) async throws -> CredentialDescriptor {
        let space = try requireSpace(spaceID)
        if let refusal = try credentialAccess(.save, in: spaceID, origin: protectionSpace.origin).refusal {
            throw CredentialVaultError(refusal)
        }

        let vaultID = try credentialVaultID(of: spaceID, keeping: existing)
        let descriptor: CredentialDescriptor
        if var existing {
            guard existing.origin == protectionSpace.origin,
                existing.scope == protectionSpace.credentialScope
            else {
                throw CredentialVaultError.invalidOrigin
            }
            existing.username = username
            existing.updatedAt = now
            existing.lastUsedAt = now
            existing.isSynchronizable =
                space.settings.credentialPreferences.syncsCrestPasswordsWithICloud
            descriptor = existing
        } else {
            descriptor = CredentialDescriptor(
                spaceID: vaultID,
                origin: protectionSpace.origin,
                scope: protectionSpace.credentialScope,
                username: username,
                createdAt: now,
                lastUsedAt: now,
                isSynchronizable:
                    space.settings.credentialPreferences.syncsCrestPasswordsWithICloud
            )
        }
        try await credentialVault.save(
            BrowserCredential(descriptor: descriptor, password: password),
            in: vaultID
        )
        return descriptor
    }

    func deleteCredential(id: UUID) async throws {
        try await deleteCredential(id: id, in: try requireShownSpaceID())
    }

    /// Deletes the password `id` names from whichever vault of the Space's
    /// group keeps it.
    func deleteCredential(id: UUID, in spaceID: UUID) async throws {
        _ = try requireSpace(spaceID)
        for vault in credentialSpaceIDs(of: spaceID) {
            guard try await credentialVault.descriptors(in: vault).contains(where: { $0.id == id }) else { continue }
            try await credentialVault.delete(id: id, in: vault)
        }
    }

    /// Rewrites, in place, each login of the Space's group whose site an
    /// earlier build stored in a spelling no page has, such as `127.1`, in
    /// the one pages use, so it fills again. Returns whether any changed.
    @discardableResult
    func respellCredentials(in spaceID: UUID) async throws -> Bool {
        let descriptors = try await savedCredentialDescriptors(in: spaceID)
        let saved = descriptors.map { SavedCredentialOrigin(id: $0.id, origin: $0.origin) }
        guard !saved.isEmpty, let respellings = try? core.query(CredentialsToRespell(saved: saved)).respelled,
            !respellings.isEmpty
        else { return false }
        for respelling in respellings {
            guard let credential = try await credential(id: respelling.id, in: spaceID) else { continue }
            let old = credential.descriptor
            let descriptor = CredentialDescriptor(
                id: old.id, spaceID: old.spaceID, origin: respelling.origin, scope: old.scope, username: old.username,
                displayName: old.displayName, createdAt: old.createdAt, updatedAt: old.updatedAt,
                lastUsedAt: old.lastUsedAt, isSynchronizable: old.isSynchronizable, sites: old.sites,
                passwordChangedAt: old.passwordChangedAt)
            try await credentialVault.save(
                BrowserCredential(descriptor: descriptor, password: credential.password), in: old.spaceID)
        }
        return true
    }

    /// Keeps `extras` beside the password of the login `id`, in whichever
    /// vault of the Space's group keeps it.
    func saveCredentialExtras(_ extras: BrowserCredentialExtras, forCredential id: UUID, in spaceID: UUID) async throws
    {
        guard let saved = try await credential(id: id, in: spaceID) else {
            throw CredentialVaultError.missingCredential
        }
        try await credentialVault.saveExtras(extras, for: saved.descriptor, in: saved.descriptor.spaceID)
    }

    /// Saves what the person changed about the login `id` in Settings: its
    /// title, username, sites, and, where given, its password and the notes
    /// and code it keeps beside it. A password that changed is stamped with
    /// when it did. Returns the login as saved.
    @discardableResult
    func editCredential(
        id: UUID,
        in spaceID: UUID,
        edit: BrowserCredentialEdit,
        now: Date = Date()
    ) async throws -> CredentialDescriptor {
        _ = try requireSpace(spaceID)
        guard let saved = try await credential(id: id, in: spaceID) else {
            throw CredentialVaultError.missingCredential
        }
        var descriptor = saved.descriptor
        let vaultID = descriptor.spaceID
        descriptor.displayName = edit.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        descriptor.username = edit.username.trimmingCharacters(in: .whitespacesAndNewlines)
        var sites: [CredentialOrigin] = []
        for site in edit.sites where site != descriptor.origin && !sites.contains(site) {
            sites.append(site)
        }
        descriptor.sites = Array(sites.prefix(CredentialDescriptor.maximumSites))
        let password = edit.password ?? saved.password
        if password != saved.password { descriptor.passwordChangedAt = now }
        descriptor.updatedAt = now
        try await credentialVault.save(BrowserCredential(descriptor: descriptor, password: password), in: vaultID)
        if let extras = edit.extras {
            try await credentialVault.saveExtras(extras, for: descriptor, in: vaultID)
        }
        return descriptor
    }

    /// Moves the logins `ids` of the Space `spaceID` into the Space
    /// `destination`, each with its notes and code, under the destination's
    /// iCloud choice. Each is written there before it leaves here, so a stop
    /// partway leaves a copy, never a loss.
    func moveCredentials(_ ids: [UUID], from spaceID: UUID, to destination: UUID) async throws {
        _ = try requireSpace(spaceID)
        let target = try requireSpace(destination)
        if let refusal = try credentialAccess(.save, in: destination).refusal {
            throw CredentialVaultError(refusal)
        }
        let targetVault = try credentialVaultID(of: destination, keeping: nil)
        let synchronizes = target.settings.credentialPreferences.syncsCrestPasswordsWithICloud
        for id in ids {
            // A login already on its way, from this window or another, is left
            // to that move.
            guard Self.credentialsBeingMoved.insert(id).inserted else { continue }
            defer { Self.credentialsBeingMoved.remove(id) }
            guard let saved = try await credential(id: id, in: spaceID) else { continue }
            let sourceVault = saved.descriptor.spaceID
            guard sourceVault != targetVault else { continue }
            let extras = try await credentialVault.extras(id: id, in: sourceVault)
            var moved = saved.moved(to: targetVault)
            moved.descriptor.isSynchronizable = synchronizes
            try await credentialVault.save(moved, in: targetVault)
            if let extras { try await credentialVault.saveExtras(extras, for: moved.descriptor, in: targetVault) }
            try await credentialVault.delete(id: id, in: sourceVault)
        }
    }

    func deleteUnreadableCredentials(in spaceID: UUID) async throws {
        _ = try requireSpace(spaceID)
        for vault in credentialSpaceIDs(of: spaceID) {
            try await credentialVault.deleteUnreadableCredentials(in: vault)
        }
    }

    func replaceCredentialInventory(
        _ credentials: [BrowserCredential],
        in spaceID: UUID
    ) async throws {
        _ = try requireSpace(spaceID)
        guard !isPrivateBrowsing else {
            throw CredentialVaultError.unavailableInPrivateBrowsing
        }
        for credential in credentials {
            guard credential.descriptor.spaceID == spaceID else {
                throw CredentialVaultError.spaceMismatch(
                    expected: spaceID,
                    actual: credential.descriptor.spaceID
                )
            }
        }
        try await credentialVault.replaceAll(credentials, in: spaceID)
    }

    private func performCredentialSave(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        now: Date
    ) async throws -> BrowserCredentialSaveResult {
        let plan = try await credentialSavePlan(
            for: candidate,
            in: spaceID,
            now: now
        )
        return try await plan.commit(candidate, in: spaceID, now: now, on: self)
    }

    /// Saves `candidate` in the Space `spaceID`, in place of `existing` when
    /// it names the account the candidate changes.
    func saveCredential(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        replacing existing: CredentialDescriptor?,
        now: Date
    ) async throws -> CredentialDescriptor {
        guard let url = URL(string: candidate.origin.description) else {
            throw CredentialVaultError.invalidOrigin
        }
        return try await saveCredential(
            username: candidate.username,
            password: candidate.password,
            for: url,
            in: spaceID,
            replacing: existing,
            now: now
        )
    }

    private func validateCredentialSaveCandidate(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        now: Date
    ) throws {
        _ = try requireSpace(spaceID)
        if let refusal = try credentialAccess(.save, in: spaceID).refusal {
            throw CredentialVaultError(refusal)
        }
        let check = CredentialSaveCheck(
            origin: candidate.origin, topLevelOrigin: candidate.topLevelOrigin,
            submittedAt: candidate.submittedAt.timeIntervalSince1970, now: now.timeIntervalSince1970)
        switch (try? core.query(check))?.validity {
        case .accepted: return
        case .insecureOrigin: throw CredentialVaultError.insecureOrigin
        case .stale: throw CredentialVaultError.staleSaveCandidate
        case nil: throw CredentialVaultError.saveDecisionUnavailable
        }
    }
}

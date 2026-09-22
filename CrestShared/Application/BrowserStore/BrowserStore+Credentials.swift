import Foundation

// MARK: - Suggestion Loading

extension BrowserStore: BrowserCredentialSuggestionLoading {
    func credentialSuggestions(
        for origin: CredentialOrigin,
        in spaceID: SpaceID
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
        guard let spaceID = selectedSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialSuggestions(for: url, in: spaceID)
    }

    func savedCredentialDescriptors(in spaceID: SpaceID) async throws -> [CredentialDescriptor] {
        guard session.space(id: spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialVault.descriptors(in: spaceID)
    }

    func credentialSuggestions(
        for url: URL,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor] {
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.credentialPreferences.isEnabled else { return [] }
        guard let origin = CredentialOrigin(url: url) else {
            throw CredentialVaultError.invalidOrigin
        }
        guard origin.isSecure else { return [] }
        return try await credentialVault.descriptors(matching: origin, in: spaceID)
    }

    func credential(id: CredentialID) async throws -> BrowserCredential? {
        guard let spaceID = selectedSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        return try await credential(id: id, in: spaceID)
    }

    func credential(id: CredentialID, in spaceID: SpaceID) async throws -> BrowserCredential? {
        guard session.space(id: spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialVault.credential(id: id, in: spaceID)
    }

    func credentialInventory(in spaceID: SpaceID) async throws -> [BrowserCredential] {
        guard session.space(id: spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
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
        in spaceID: SpaceID
    ) async throws -> BrowserCredential? {
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.credentialPreferences.isEnabled else { return nil }
        guard protectionSpace.origin.isSecure else { return nil }
        let descriptors = try await credentialVault.descriptors(
            matching: protectionSpace,
            in: spaceID
        )
        // Without a recency answer from the core, nothing is filled.
        guard let descriptor = try? BrowserCorePolicy.mostRecentCredential(descriptors) else {
            return nil
        }
        return try await credentialVault.credential(id: descriptor.id, in: spaceID)
    }
}

// MARK: - Preferences

extension BrowserStore {
    func updateCredentialPreferences(
        _ preferences: BrowserCredentialPreferences,
        in spaceID: SpaceID
    ) {
        if isTemporaryWorkspace {
            temporaryProfileSettingsAuthority(in: spaceID)?.updateCredentialPreferences(preferences, in: spaceID)
            return
        }
        guard session.space(id: spaceID) != nil else { return }
        guard setCoreSpaceValue("space.credential_preferences", preferences, in: spaceID) else { return }
        persist(scope: .core)
    }

    func setCrestPasswordSynchronization(
        _ isSynchronizable: Bool,
        in spaceID: SpaceID
    ) async throws {
        if isTemporaryWorkspace {
            guard let source = temporaryProfileSettingsAuthority(in: spaceID) else {
                throw CredentialVaultError.missingSpace
            }
            try await source.setCrestPasswordSynchronization(isSynchronizable, in: spaceID)
            return
        }
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.credentialPreferences.syncsCrestPasswordsWithICloud != isSynchronizable else {
            return
        }

        try await credentialVault.setSynchronizable(isSynchronizable, in: spaceID)
        guard let current = self.space(matching: BrowserSpaceRuntimeAssignment(space: space)) else {
            throw CredentialVaultError.missingSpace
        }
        var preferences = current.credentialPreferences
        preferences.syncsCrestPasswordsWithICloud = isSynchronizable
        // The native credential operation completed for this profile. Persist
        // its corresponding policy through the same session authority.
        if !setCoreSpaceValue("space.credential_preferences", preferences, in: spaceID),
            session.space(id: spaceID)?.credentialPreferences != preferences {
            throw CredentialVaultError.preferenceUpdateFailed
        }
        persist(scope: .core)
    }

}

// MARK: - Saving

extension BrowserStore {
    /// The core matches the account and plans the save from descriptors
    /// alone. The stored password is compared here and only the answer is
    /// passed on. A core that cannot answer fails the plan: nothing is saved.
    func credentialSavePlan(
        for candidate: BrowserCredentialSaveCandidate,
        in spaceID: SpaceID,
        now: Date = .now
    ) async throws -> BrowserCredentialSavePlan {
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        let descriptors = try await credentialVault.descriptors(
            matching: candidate.origin,
            in: spaceID
        )
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        let descriptor = try BrowserCorePolicy.credentialSaveMatch(
            username: candidate.username,
            in: descriptors
        )
        var storedPasswordMatches: Bool?
        if let descriptor {
            let credential = try await credentialVault.credential(
                id: descriptor.id,
                in: spaceID
            )
            try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
            storedPasswordMatches = credential.map { $0.password == candidate.password }
        }
        let plan = try BrowserCorePolicy.credentialSavePlan(
            match: descriptor?.id,
            storedPasswordMatches: storedPasswordMatches
        )
        switch (plan, descriptor) {
        case (.create, _): return .create
        case (.update, let descriptor?): return .update(descriptor)
        case (.alreadyStored, let descriptor?): return .alreadyStored(descriptor)
        default: throw CredentialVaultError.saveDecisionUnavailable
        }
    }

    func commitCredentialSave(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: SpaceID,
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
        guard let spaceID = selectedSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        return try await saveCredential(
            username: username,
            password: password,
            for: url,
            in: spaceID,
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
        in spaceID: SpaceID,
        displayName: String? = nil,
        replacing existing: CredentialDescriptor? = nil,
        isSynchronizable: Bool? = nil,
        now: Date = Date()
    ) async throws -> CredentialDescriptor {
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard !isPrivateBrowsing else {
            throw CredentialVaultError.unavailableInPrivateBrowsing
        }
        guard space.credentialPreferences.isEnabled else {
            throw CredentialVaultError.credentialManagerDisabled
        }
        let resolvedSynchronization =
            isSynchronizable
            ?? space.credentialPreferences.syncsCrestPasswordsWithICloud
        guard let origin = CredentialOrigin(url: url) else {
            throw CredentialVaultError.invalidOrigin
        }
        guard origin.isSecure else {
            throw CredentialVaultError.insecureOrigin
        }

        let descriptor: CredentialDescriptor
        if var existing {
            guard existing.spaceID == spaceID else {
                throw CredentialVaultError.spaceMismatch(
                    expected: spaceID,
                    actual: existing.spaceID
                )
            }
            guard existing.origin == origin else {
                throw CredentialVaultError.invalidOrigin
            }
            existing.username = username
            existing.displayName = displayName?.nilIfEmpty ?? existing.displayName
            existing.updatedAt = now
            existing.isSynchronizable = resolvedSynchronization
            descriptor = existing
        } else {
            descriptor = CredentialDescriptor(
                spaceID: spaceID,
                origin: origin,
                username: username,
                displayName: displayName?.nilIfEmpty,
                createdAt: now,
                isSynchronizable: resolvedSynchronization
            )
        }
        try await credentialVault.save(
            BrowserCredential(descriptor: descriptor, password: password),
            in: spaceID
        )
        return descriptor
    }

    @discardableResult
    func saveHTTPAuthenticationCredential(
        username: String,
        password: String,
        protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: SpaceID,
        replacing existing: CredentialDescriptor? = nil,
        now: Date = Date()
    ) async throws -> CredentialDescriptor {
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard !isPrivateBrowsing else {
            throw CredentialVaultError.unavailableInPrivateBrowsing
        }
        guard space.credentialPreferences.isEnabled else {
            throw CredentialVaultError.credentialManagerDisabled
        }
        guard protectionSpace.origin.isSecure else {
            throw CredentialVaultError.insecureOrigin
        }

        let descriptor: CredentialDescriptor
        if var existing {
            guard existing.spaceID == spaceID else {
                throw CredentialVaultError.spaceMismatch(
                    expected: spaceID,
                    actual: existing.spaceID
                )
            }
            guard existing.origin == protectionSpace.origin,
                existing.scope == protectionSpace.credentialScope
            else {
                throw CredentialVaultError.invalidOrigin
            }
            existing.username = username
            existing.updatedAt = now
            existing.lastUsedAt = now
            existing.isSynchronizable =
                space.credentialPreferences.syncsCrestPasswordsWithICloud
            descriptor = existing
        } else {
            descriptor = CredentialDescriptor(
                spaceID: spaceID,
                origin: protectionSpace.origin,
                scope: protectionSpace.credentialScope,
                username: username,
                createdAt: now,
                lastUsedAt: now,
                isSynchronizable:
                    space.credentialPreferences.syncsCrestPasswordsWithICloud
            )
        }
        try await credentialVault.save(
            BrowserCredential(descriptor: descriptor, password: password),
            in: spaceID
        )
        return descriptor
    }

    func deleteCredential(id: CredentialID) async throws {
        guard let spaceID = selectedSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        try await deleteCredential(id: id, in: spaceID)
    }

    func deleteCredential(id: CredentialID, in spaceID: SpaceID) async throws {
        guard session.space(id: spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        try await credentialVault.delete(id: id, in: spaceID)
    }

    func replaceCredentialInventory(
        _ credentials: [BrowserCredential],
        in spaceID: SpaceID
    ) async throws {
        guard session.space(id: spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
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
        in spaceID: SpaceID,
        now: Date
    ) async throws -> BrowserCredentialSaveResult {
        let plan = try await credentialSavePlan(
            for: candidate,
            in: spaceID,
            now: now
        )
        switch plan {
        case .create:
            let descriptor = try await saveCredential(
                candidate,
                in: spaceID,
                replacing: nil,
                now: now
            )
            return BrowserCredentialSaveResult(
                descriptor: descriptor,
                disposition: .created
            )
        case .update(let existing):
            let descriptor = try await saveCredential(
                candidate,
                in: spaceID,
                replacing: existing,
                now: now
            )
            return BrowserCredentialSaveResult(
                descriptor: descriptor,
                disposition: .updated
            )
        case .alreadyStored(let existing):
            return BrowserCredentialSaveResult(
                descriptor: existing,
                disposition: .unchanged
            )
        }
    }

    private func saveCredential(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: SpaceID,
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
        in spaceID: SpaceID,
        now: Date
    ) throws {
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard !isPrivateBrowsing else {
            throw CredentialVaultError.unavailableInPrivateBrowsing
        }
        guard space.credentialPreferences.isEnabled else {
            throw CredentialVaultError.credentialManagerDisabled
        }
        switch BrowserCorePolicy.credentialSaveValidity(for: candidate, now: now) {
        case .accepted: return
        case .insecureOrigin: throw CredentialVaultError.insecureOrigin
        case .stale: throw CredentialVaultError.staleSaveCandidate
        case nil: throw CredentialVaultError.saveDecisionUnavailable
        }
    }
}

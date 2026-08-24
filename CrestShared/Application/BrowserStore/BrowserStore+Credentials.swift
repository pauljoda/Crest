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
        guard
            let descriptor = descriptors.max(
                by: BrowserCredentialRecencyPolicy.isLessRecent
            )
        else {
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
        guard session.space(id: spaceID) != nil else { return }
        session.updateCredentialPreferences(preferences, in: spaceID)
        persist(scope: .core)
    }

    func setCrestPasswordSynchronization(
        _ isSynchronizable: Bool,
        in spaceID: SpaceID
    ) async throws {
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.credentialPreferences.syncsCrestPasswordsWithICloud != isSynchronizable else {
            return
        }

        try await credentialVault.setSynchronizable(isSynchronizable, in: spaceID)
        var preferences = space.credentialPreferences
        preferences.syncsCrestPasswordsWithICloud = isSynchronizable
        session.updateCredentialPreferences(preferences, in: spaceID)
        persist(scope: .core)
    }

}

// MARK: - Saving

extension BrowserStore {
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
        let matchingDescriptors = descriptors.filter {
            $0.username.caseInsensitiveCompare(candidate.username) == .orderedSame
        }
        guard
            let descriptor = matchingDescriptors.max(
                by: BrowserCredentialRecencyPolicy.isLessRecent
            )
        else {
            return .create
        }
        guard
            let credential = try await credentialVault.credential(
                id: descriptor.id,
                in: spaceID
            )
        else {
            return .create
        }
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        return credential.password == candidate.password
            ? .alreadyStored(descriptor)
            : .update(descriptor)
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
            existing.displayName = BrowserStoredStringPolicy.normalized(displayName) ?? existing.displayName
            existing.updatedAt = now
            existing.isSynchronizable = resolvedSynchronization
            descriptor = existing
        } else {
            descriptor = CredentialDescriptor(
                spaceID: spaceID,
                origin: origin,
                username: username,
                displayName: BrowserStoredStringPolicy.normalized(displayName),
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
        guard
            BrowserCredentialCapturePolicy.accepts(
                frameOrigin: candidate.origin,
                topLevelOrigin: candidate.topLevelOrigin
            )
        else {
            throw CredentialVaultError.insecureOrigin
        }
        guard BrowserCredentialCapturePolicy.isCurrent(candidate, now: now) else {
            throw CredentialVaultError.staleSaveCandidate
        }
    }
}

import Foundation

/// Crest's saved passwords in the Keychain, one service per Space. Listing a
/// Space leaves out an item that no longer reads back, so one bad item never
/// makes the rest of the Space unreadable; `unreadableCredentialCount(in:)`
/// reports what was left out, and only `deleteUnreadableCredentials(in:)`
/// removes it. Writes take turns: the actor answers other calls while a write
/// waits on the Keychain, and a write never reads or restores over what
/// another is halfway through changing.
actor KeychainCredentialVault: CredentialVault {
    // MARK: - Variables

    private let store: any CredentialKeychainStoring
    private let servicePrefix: String
    private let codec = CredentialKeychainCodec()
    /// Whether a write holds the vault, and the writes waiting their turn.
    private var isWriting = false
    private var waitingWrites: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initializers

    init(
        store: any CredentialKeychainStoring,
        servicePrefix: String = CredentialKeychainNamespace.productionPrefix
    ) {
        self.store = store
        self.servicePrefix = servicePrefix
    }

    // MARK: - Actions - Reading

    func descriptors(in spaceID: UUID) async throws -> [CredentialDescriptor] {
        try await readableDescriptors(in: spaceID)
            .sorted(by: Self.descriptorOrder)
    }

    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        try await readableDescriptors(in: spaceID)
            .filter { $0.origin == origin && $0.scope == .webForm }
            .sorted(by: Self.descriptorOrder)
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        try await readableDescriptors(in: spaceID)
            .filter {
                $0.origin == protectionSpace.origin
                    && $0.scope == protectionSpace.credentialScope
            }
            .sorted(by: Self.descriptorOrder)
    }

    func unreadableCredentialCount(in spaceID: UUID) async throws -> Int {
        try await store.descriptorItems(in: service(for: spaceID))
            .count { !reads($0, in: spaceID) }
    }

    func credential(
        id: UUID,
        in spaceID: UUID
    ) async throws -> BrowserCredential? {
        let account = id.uuidString.lowercased()
        guard
            let item = try await store.item(
                account: account,
                in: service(for: spaceID)
            )
        else {
            return nil
        }
        return try codec.credential(
            from: item,
            expectedID: id,
            expectedSpaceID: spaceID
        )
    }

    // MARK: - Actions - Writing

    func save(_ credential: BrowserCredential, in spaceID: UUID) async throws {
        let item = try codec.item(
            for: credential,
            expectedSpaceID: spaceID
        )
        try await writing {
            try await store.upsert(item, in: service(for: spaceID))
        }
    }

    /// Makes the Space hold `credentials`: writes each one that differs from
    /// what the Space holds, then removes what they leave out. Removing comes
    /// last, so a stop partway leaves every password the person keeps, as it
    /// was or as replaced. A failure undoes exactly what the replacement did.
    func replaceAll(
        _ credentials: [BrowserCredential],
        in spaceID: UUID
    ) async throws {
        let service = service(for: spaceID)
        let replacementItems = try credentials.map {
            try codec.item(for: $0, expectedSpaceID: spaceID)
        }
        let replacementAccounts = Set(replacementItems.map(\.account))
        guard replacementAccounts.count == replacementItems.count else {
            throw CredentialVaultError.malformedStoredCredential
        }
        try await writing {
            let originalItems = try await store.items(in: service)
            let originals = Dictionary(originalItems.map { ($0.account, $0) }) { first, _ in first }
            let changedItems = replacementItems.filter { originals[$0.account] != $0 }
            // An item that no longer reads back is in no inventory a caller can
            // name, so a replacement keeps it.
            let leftOutItems = originalItems.filter {
                !replacementAccounts.contains($0.account) && reads($0, in: spaceID)
            }
            var written: [CredentialKeychainItem] = []
            var removed: [CredentialKeychainItem] = []
            do {
                for item in changedItems {
                    try await store.upsert(item, in: service)
                    written.append(item)
                }
                for item in leftOutItems {
                    try await store.delete(account: item.account, in: service)
                    removed.append(item)
                }
            } catch {
                do {
                    for item in written.reversed() {
                        if let original = originals[item.account] {
                            try await store.upsert(original, in: service)
                        } else {
                            try await store.delete(account: item.account, in: service)
                        }
                    }
                    for item in removed {
                        try await store.upsert(item, in: service)
                    }
                } catch {
                    throw CredentialVaultError.atomicReplacementRestoreFailed
                }
                throw error
            }
        }
    }

    func setSynchronizable(
        _ isSynchronizable: Bool,
        in spaceID: UUID
    ) async throws {
        let service = service(for: spaceID)
        try await writing {
            let originalItems = try await store.items(in: service)
            var migratedOriginalItems: [CredentialKeychainItem] = []

            do {
                for item in originalItems
                where item.isSynchronizable != isSynchronizable && reads(item, in: spaceID) {
                    let migratedItem = try codec.migratedItem(
                        from: item,
                        isSynchronizable: isSynchronizable,
                        expectedSpaceID: spaceID
                    )
                    try await store.upsert(migratedItem, in: service)
                    migratedOriginalItems.append(item)
                }
            } catch {
                // Each item changes in place, so one that stays moved is still
                // whole, and the next change moves the rest.
                for originalItem in migratedOriginalItems.reversed() {
                    try? await store.upsert(originalItem, in: service)
                }
                throw error
            }
        }
    }

    func delete(id: UUID, in spaceID: UUID) async throws {
        try await writing {
            try await store.delete(
                account: id.uuidString.lowercased(),
                in: service(for: spaceID)
            )
        }
    }

    func deleteAll(in spaceID: UUID) async throws {
        try await writing {
            try await store.deleteAll(in: service(for: spaceID))
        }
    }

    func deleteUnreadableCredentials(in spaceID: UUID) async throws {
        let service = service(for: spaceID)
        try await writing {
            for item in try await store.descriptorItems(in: service) where !reads(item, in: spaceID) {
                try await store.delete(account: item.account, in: service)
            }
        }
    }

    // MARK: - Actions - Turns

    /// Runs `write` once no other write holds the vault, holding it until
    /// `write` ends, when the write that waited longest takes it.
    private func writing<Result>(_ write: () async throws -> Result) async rethrows -> Result {
        if isWriting {
            await withCheckedContinuation { waitingWrites.append($0) }
        } else {
            isWriting = true
        }
        defer {
            if waitingWrites.isEmpty {
                isWriting = false
            } else {
                waitingWrites.removeFirst().resume()
            }
        }
        return try await write()
    }

    // MARK: - Actions - Items

    private func readableDescriptors(in spaceID: UUID) async throws -> [CredentialDescriptor] {
        try await store.descriptorItems(in: service(for: spaceID))
            .compactMap { try? codec.descriptor(from: $0, expectedSpaceID: spaceID) }
    }

    private func reads(_ item: CredentialKeychainDescriptorItem, in spaceID: UUID) -> Bool {
        (try? codec.descriptor(from: item, expectedSpaceID: spaceID)) != nil
    }

    private func reads(_ item: CredentialKeychainItem, in spaceID: UUID) -> Bool {
        (try? codec.descriptor(from: item, expectedSpaceID: spaceID)) != nil
    }

    private func service(for spaceID: UUID) -> String {
        CredentialKeychainNamespace.service(for: spaceID, prefix: servicePrefix)
    }

    private static func descriptorOrder(
        _ lhs: CredentialDescriptor,
        _ rhs: CredentialDescriptor
    ) -> Bool {
        let usernameOrder = lhs.username.localizedCaseInsensitiveCompare(rhs.username)
        if usernameOrder != .orderedSame {
            return usernameOrder == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

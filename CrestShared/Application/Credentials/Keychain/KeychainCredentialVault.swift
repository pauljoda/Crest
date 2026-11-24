import Foundation

/// Crest's saved passwords in the Keychain, one service per Space. Listing a
/// Space leaves out an item that no longer reads back, so one bad item never
/// makes the rest of the Space unreadable; `unreadableCredentialCount(in:)`
/// reports what was left out, and only `deleteUnreadableCredentials(in:)`
/// removes it. Writes take turns: the actor answers other calls while a write
/// waits on the Keychain, and a write never reads or restores over what
/// another is halfway through changing. What a login keeps beside its
/// password, its notes and code key, lives in a companion item under the
/// login's own account in the Space's extras service, which goes with it.
actor KeychainCredentialVault: CredentialVault {
    // MARK: - Variables

    private let store: any CredentialKeychainStoring
    nonisolated let servicePrefix: String
    private let codec = CredentialKeychainCodec()
    /// Whether passwords saved for each origin fill a page at the first, in
    /// order, which the core answers in production.
    private let fills: @Sendable (CredentialOrigin, [CredentialOrigin]) throws -> [Bool]
    /// Whether a write holds the vault, and the writes waiting their turn.
    private var isWriting = false
    private var waitingWrites: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initializers

    init(
        store: any CredentialKeychainStoring,
        servicePrefix: String = CredentialKeychainNamespace.productionPrefix,
        fills: @escaping @Sendable (CredentialOrigin, [CredentialOrigin]) throws -> [Bool] = { page, saved in
            saved.map { $0 == page }
        }
    ) {
        self.store = store
        self.servicePrefix = servicePrefix
        self.fills = fills
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
        try filling(origin, from: await readableDescriptors(in: spaceID).filter { $0.scope == .webForm })
            .sorted(by: Self.descriptorOrder)
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        try filling(
            protectionSpace.origin,
            from: await readableDescriptors(in: spaceID).filter { $0.scope == protectionSpace.credentialScope }
        )
        .sorted(by: Self.descriptorOrder)
    }

    func unreadableCredentialCount(in spaceID: UUID) async throws -> Int {
        try await store.descriptorItems(in: service(for: spaceID))
            .count { !reads($0, in: spaceID) }
    }

    /// One read of the Space's service answers both, where settings asked the
    /// Keychain for the whole service twice.
    func inventory(in spaceID: UUID) async throws -> CredentialInventory {
        let items = try await store.descriptorItems(in: service(for: spaceID))
        let descriptors = items.compactMap { try? codec.descriptor(from: $0, expectedSpaceID: spaceID) }
        let readable = Set(descriptors.map(\.id))
        var extras: [UUID: BrowserCredentialExtrasSummary] = [:]
        for item in try await store.descriptorItems(in: extrasService(for: spaceID)) {
            guard let owned = codec.extrasSummary(from: item), readable.contains(owned.ownerID) else { continue }
            extras[owned.ownerID] = owned.summary
        }
        try await removeOrphanedExtras(keeping: Set(items.map(\.account)), in: spaceID)
        return CredentialInventory(
            descriptors: descriptors.sorted(by: Self.descriptorOrder),
            unreadableCount: items.count - descriptors.count,
            extras: extras)
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
                // A login that went takes its notes and code with it.
                for item in removed {
                    try? await removeCompanion(of: item.account, in: spaceID)
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
                // A login's notes and code follow it into or out of iCloud.
                let extrasService = extrasService(for: spaceID)
                for item in try await store.items(in: extrasService)
                where item.isSynchronizable != isSynchronizable && isCompanion(item) {
                    try await store.upsert(
                        codec.migratedExtrasItem(from: item, isSynchronizable: isSynchronizable), in: extrasService)
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
        let account = codec.account(for: id)
        try await writing {
            try await store.delete(account: account, in: service(for: spaceID))
            try await removeCompanion(of: account, in: spaceID)
        }
    }

    func deleteAll(in spaceID: UUID) async throws {
        try await writing {
            try await store.deleteAll(in: service(for: spaceID))
            try await store.deleteAll(in: extrasService(for: spaceID))
        }
    }

    func deleteUnreadableCredentials(in spaceID: UUID) async throws {
        let service = service(for: spaceID)
        try await writing {
            for item in try await store.descriptorItems(in: service) where !reads(item, in: spaceID) {
                try await store.delete(account: item.account, in: service)
                try await removeCompanion(of: item.account, in: spaceID)
            }
        }
    }

    // MARK: - Actions - Extras

    func extras(id: UUID, in spaceID: UUID) async throws -> BrowserCredentialExtras? {
        guard let item = try await store.item(account: codec.account(for: id), in: extrasService(for: spaceID)) else {
            return nil
        }
        guard let extras = codec.extras(from: item, expectedID: id) else {
            throw CredentialVaultError.malformedStoredCredential
        }
        return extras
    }

    func saveExtras(_ extras: BrowserCredentialExtras, for descriptor: CredentialDescriptor, in spaceID: UUID)
        async throws
    {
        guard descriptor.spaceID == spaceID else {
            throw CredentialVaultError.spaceMismatch(expected: spaceID, actual: descriptor.spaceID)
        }
        let item = extras.isEmpty ? nil : try codec.extrasItem(for: extras, of: descriptor)
        try await writing {
            // Extras belong to a saved login; the login is read again here so a
            // deletion that just finished never leaves an orphan behind.
            guard
                let login = try await store.item(account: codec.account(for: descriptor.id), in: service(for: spaceID)),
                (try? codec.descriptor(from: login, expectedSpaceID: spaceID)) != nil
            else {
                throw CredentialVaultError.missingCredential
            }
            if let item {
                try await store.upsert(
                    CredentialKeychainItem(
                        account: item.account, metadata: item.metadata, secret: item.secret,
                        isSynchronizable: login.isSynchronizable),
                    in: extrasService(for: spaceID))
            } else {
                try await store.delete(account: codec.account(for: descriptor.id), in: extrasService(for: spaceID))
            }
        }
    }

    /// Removes the companion item of the login `account`, where it has one.
    private func removeCompanion(of account: String, in spaceID: UUID) async throws {
        let extrasService = extrasService(for: spaceID)
        guard let item = try await store.item(account: account, in: extrasService), isCompanion(item) else { return }
        try await store.delete(account: account, in: extrasService)
    }

    /// Whether `item` is a companion this build reads, rather than anything
    /// else stored under the same account.
    private func isCompanion(_ item: CredentialKeychainItem) -> Bool {
        codec.extrasSummary(
            from: CredentialKeychainDescriptorItem(
                account: item.account, metadata: item.metadata, isSynchronizable: item.isSynchronizable)) != nil
    }

    /// Removes companion items whose login is gone, as when an older build
    /// deleted the login, keeping any whose login is still stored even if it
    /// no longer reads back.
    private func removeOrphanedExtras(keeping accounts: Set<String>, in spaceID: UUID) async throws {
        let extrasService = extrasService(for: spaceID)
        let orphans = try await store.descriptorItems(in: extrasService)
            .filter { !accounts.contains($0.account) && codec.extrasSummary(from: $0) != nil }
        guard !orphans.isEmpty else { return }
        try await writing {
            let stored = Set(try await store.descriptorItems(in: service(for: spaceID)).map(\.account))
            for orphan in orphans where !stored.contains(orphan.account) {
                try await store.delete(account: orphan.account, in: extrasService)
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

    /// The descriptors among `descriptors` whose passwords fill a page at
    /// `origin`: those saved for it, and those whose origin the core reads as
    /// it, such as an IP address an earlier import kept in another spelling.
    private func filling(
        _ origin: CredentialOrigin,
        from descriptors: [CredentialDescriptor]
    ) throws -> [CredentialDescriptor] {
        // Each site a login names is asked about, the one it was saved for and
        // the ones the person added.
        let others = descriptors.filter { !$0.origins.contains(origin) }
            .flatMap { descriptor in descriptor.origins.map { (descriptor.id, $0) } }
        let othersFill: [Bool]
        do {
            othersFill = try fills(origin, others.map(\.1))
        } catch Rejection.invalidCredentialOrigin {
            // No page has such an origin, but if one did, its own passwords still fill it.
            othersFill = []
        }
        let filling = Set(zip(others, othersFill).filter(\.1).map(\.0.0))
        return descriptors.filter { $0.origins.contains(origin) || filling.contains($0.id) }
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

    private func extrasService(for spaceID: UUID) -> String {
        CredentialKeychainNamespace.extrasService(for: spaceID, prefix: servicePrefix)
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

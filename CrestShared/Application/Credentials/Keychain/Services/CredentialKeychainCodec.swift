import Foundation

struct CredentialKeychainCodec {
    /// Keys in a fixed order, so the same login always writes the same bytes
    /// and a replacement rewrites only what changed. Readers don't depend on
    /// the order.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
    private let decoder = JSONDecoder()

    func item(
        for credential: BrowserCredential,
        expectedSpaceID: UUID
    ) throws -> CredentialKeychainItem {
        guard credential.descriptor.spaceID == expectedSpaceID else {
            throw CredentialVaultError.spaceMismatch(
                expected: expectedSpaceID,
                actual: credential.descriptor.spaceID
            )
        }
        let item = CredentialKeychainItem(
            account: account(for: credential.descriptor.id),
            metadata: try encoder.encode(credential.descriptor),
            secret: Data(credential.password.utf8),
            isSynchronizable: credential.descriptor.isSynchronizable
        )
        // Reading a Space decodes every item, so an item that would not read
        // back is refused here instead of making the whole Space unreadable.
        _ = try descriptor(from: item, expectedSpaceID: expectedSpaceID)
        return item
    }

    func descriptor(
        from item: CredentialKeychainItem,
        expectedSpaceID: UUID
    ) throws -> CredentialDescriptor {
        try descriptor(
            account: item.account,
            metadata: item.metadata,
            isSynchronizable: item.isSynchronizable,
            expectedSpaceID: expectedSpaceID
        )
    }

    func descriptor(
        from item: CredentialKeychainDescriptorItem,
        expectedSpaceID: UUID
    ) throws -> CredentialDescriptor {
        try descriptor(
            account: item.account,
            metadata: item.metadata,
            isSynchronizable: item.isSynchronizable,
            expectedSpaceID: expectedSpaceID
        )
    }

    func credential(
        from item: CredentialKeychainItem,
        expectedID: UUID,
        expectedSpaceID: UUID
    ) throws -> BrowserCredential {
        let descriptor = try descriptor(
            from: item,
            expectedSpaceID: expectedSpaceID
        )
        guard descriptor.id == expectedID,
            let password = String(data: item.secret, encoding: .utf8)
        else {
            throw CredentialVaultError.malformedStoredCredential
        }
        return BrowserCredential(descriptor: descriptor, password: password)
    }

    func migratedItem(
        from item: CredentialKeychainItem,
        isSynchronizable: Bool,
        expectedSpaceID: UUID
    ) throws -> CredentialKeychainItem {
        var descriptor = try descriptor(
            from: item,
            expectedSpaceID: expectedSpaceID
        )
        descriptor.isSynchronizable = isSynchronizable
        return CredentialKeychainItem(
            account: item.account,
            metadata: try encoder.encode(descriptor),
            secret: item.secret,
            isSynchronizable: isSynchronizable
        )
    }

    private func descriptor(
        account: String,
        metadata: Data,
        isSynchronizable: Bool,
        expectedSpaceID: UUID
    ) throws -> CredentialDescriptor {
        guard
            let descriptor = try? decoder.decode(
                CredentialDescriptor.self,
                from: metadata
            ), descriptor.spaceID == expectedSpaceID,
            self.account(for: descriptor.id) == account,
            descriptor.isSynchronizable == isSynchronizable
        else {
            throw CredentialVaultError.malformedStoredCredential
        }
        return descriptor
    }

    func account(for id: UUID) -> String {
        id.uuidString.lowercased()
    }

    // MARK: - Actions - Extras

    /// The companion item keeping `extras` for the login `descriptor`
    /// describes: what it holds in the open metadata, the secrets themselves
    /// in the item's data, and the login's iCloud choice.
    func extrasItem(for extras: BrowserCredentialExtras, of descriptor: CredentialDescriptor) throws
        -> CredentialKeychainItem
    {
        guard extras.notes.count <= BrowserCredentialExtras.maximumNotesLength else {
            throw CredentialVaultError.malformedStoredCredential
        }
        return CredentialKeychainItem(
            account: account(for: descriptor.id),
            metadata: try encoder.encode(
                StoredExtrasMetadata(
                    version: StoredExtrasMetadata.currentVersion, ownerID: descriptor.id, summary: extras.summary)),
            secret: try encoder.encode(StoredExtrasSecret(notes: extras.notes.nilIfEmpty, codeLink: extras.codeLink)),
            isSynchronizable: descriptor.isSynchronizable)
    }

    /// The extras a companion item keeps, or nil when it isn't one this
    /// build reads.
    func extras(from item: CredentialKeychainItem, expectedID: UUID) -> BrowserCredentialExtras? {
        guard extrasSummary(account: item.account, metadata: item.metadata, expectedID: expectedID) != nil,
            let secret = try? decoder.decode(StoredExtrasSecret.self, from: item.secret)
        else { return nil }
        return BrowserCredentialExtras(notes: secret.notes ?? "", codeLink: secret.codeLink)
    }

    /// What a companion item says it keeps, read without its secrets, with
    /// the login it belongs to; nil when it isn't one this build reads.
    func extrasSummary(from item: CredentialKeychainDescriptorItem) -> (
        ownerID: UUID, summary: BrowserCredentialExtrasSummary
    )? {
        guard let metadata = try? decoder.decode(StoredExtrasMetadata.self, from: item.metadata),
            metadata.version <= StoredExtrasMetadata.currentVersion,
            account(for: metadata.ownerID) == item.account
        else { return nil }
        return (metadata.ownerID, metadata.summary)
    }

    /// The companion item `item` again, under the login's new iCloud choice.
    func migratedExtrasItem(from item: CredentialKeychainItem, isSynchronizable: Bool) -> CredentialKeychainItem {
        CredentialKeychainItem(
            account: item.account, metadata: item.metadata, secret: item.secret, isSynchronizable: isSynchronizable)
    }

    private func extrasSummary(account: String, metadata: Data, expectedID: UUID) -> BrowserCredentialExtrasSummary? {
        guard let stored = try? decoder.decode(StoredExtrasMetadata.self, from: metadata),
            stored.ownerID == expectedID, self.account(for: expectedID) == account,
            stored.version <= StoredExtrasMetadata.currentVersion
        else { return nil }
        return stored.summary
    }
}

// MARK: - Types

/// What a companion item says in the open: its format, the login it belongs
/// to, and whether it keeps notes or a code.
private struct StoredExtrasMetadata: Codable {
    static let currentVersion = 1

    let version: Int
    let ownerID: UUID
    let summary: BrowserCredentialExtrasSummary
}

/// What a companion item keeps as its secret.
private struct StoredExtrasSecret: Codable {
    let notes: String?
    let codeLink: String?
}

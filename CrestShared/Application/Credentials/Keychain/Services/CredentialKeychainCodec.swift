import Foundation

struct CredentialKeychainCodec {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func item(
        for credential: BrowserCredential,
        expectedSpaceID: SpaceID
    ) throws -> CredentialKeychainItem {
        guard credential.descriptor.spaceID == expectedSpaceID else {
            throw CredentialVaultError.spaceMismatch(
                expected: expectedSpaceID,
                actual: credential.descriptor.spaceID
            )
        }
        return CredentialKeychainItem(
            account: account(for: credential.descriptor.id),
            metadata: try encoder.encode(credential.descriptor),
            secret: Data(credential.password.utf8),
            isSynchronizable: credential.descriptor.isSynchronizable
        )
    }

    func descriptor(
        from item: CredentialKeychainItem,
        expectedSpaceID: SpaceID
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
        expectedSpaceID: SpaceID
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
        expectedID: CredentialID,
        expectedSpaceID: SpaceID
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
        expectedSpaceID: SpaceID
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
        expectedSpaceID: SpaceID
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

    private func account(for id: CredentialID) -> String {
        id.rawValue.uuidString.lowercased()
    }
}

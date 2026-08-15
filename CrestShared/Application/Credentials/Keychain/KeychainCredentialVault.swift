import Foundation

actor KeychainCredentialVault: CredentialVault {
    private let store: any CredentialKeychainStoring
    private let servicePrefix: String
    private let codec = CredentialKeychainCodec()

    init(
        store: any CredentialKeychainStoring,
        servicePrefix: String = CredentialKeychainNamespace.productionPrefix
    ) {
        self.store = store
        self.servicePrefix = servicePrefix
    }

    func descriptors(in spaceID: SpaceID) async throws -> [CredentialDescriptor] {
        let items = try await store.descriptorItems(in: service(for: spaceID))
        return
            try items
            .map { try codec.descriptor(from: $0, expectedSpaceID: spaceID) }
            .sorted(by: Self.descriptorOrder)
    }

    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor] {
        let items = try await store.descriptorItems(in: service(for: spaceID))
        return
            try items
            .map { try codec.descriptor(from: $0, expectedSpaceID: spaceID) }
            .filter { $0.origin == origin && $0.scope == .webForm }
            .sorted(by: Self.descriptorOrder)
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor] {
        let items = try await store.descriptorItems(in: service(for: spaceID))
        return
            try items
            .map { try codec.descriptor(from: $0, expectedSpaceID: spaceID) }
            .filter {
                $0.origin == protectionSpace.origin
                    && $0.scope == protectionSpace.credentialScope
            }
            .sorted(by: Self.descriptorOrder)
    }

    func credential(
        id: CredentialID,
        in spaceID: SpaceID
    ) async throws -> BrowserCredential? {
        let account = id.rawValue.uuidString.lowercased()
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

    func save(_ credential: BrowserCredential, in spaceID: SpaceID) async throws {
        let item = try codec.item(
            for: credential,
            expectedSpaceID: spaceID
        )
        try await store.upsert(item, in: service(for: spaceID))
    }

    func setSynchronizable(
        _ isSynchronizable: Bool,
        in spaceID: SpaceID
    ) async throws {
        let service = service(for: spaceID)
        let originalItems = try await store.items(in: service)
        var migratedOriginalItems: [CredentialKeychainItem] = []

        do {
            for item in originalItems where item.isSynchronizable != isSynchronizable {
                let migratedItem = try codec.migratedItem(
                    from: item,
                    isSynchronizable: isSynchronizable,
                    expectedSpaceID: spaceID
                )
                try await store.upsert(migratedItem, in: service)
                migratedOriginalItems.append(item)
            }
        } catch {
            for originalItem in migratedOriginalItems.reversed() {
                try? await store.upsert(originalItem, in: service)
            }
            throw error
        }
    }

    func delete(id: CredentialID, in spaceID: SpaceID) async throws {
        try await store.delete(
            account: id.rawValue.uuidString.lowercased(),
            in: service(for: spaceID)
        )
    }

    func deleteAll(in spaceID: SpaceID) async throws {
        try await store.deleteAll(in: service(for: spaceID))
    }

    private func service(for spaceID: SpaceID) -> String {
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
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }
}

import Foundation

// MARK: - Types

/// Which of the person's records an autofill item is: an address or a
/// payment card, each kept in a Keychain service of its own.
struct BrowserAutofillRecordKind: Hashable, Sendable {
    static let address = BrowserAutofillRecordKind(serviceSuffix: "autofill.address")
    static let card = BrowserAutofillRecordKind(serviceSuffix: "autofill.card")

    let serviceSuffix: String
}

/// Where Crest keeps the person's addresses and payment cards: one service
/// each in the Keychain, shared by every Space, one item per record under the
/// record's id. What a list shows is in the item's open metadata; the record
/// itself is the item's secret. A private window keeps none.
actor BrowserAutofillVault {
    // MARK: - Static Variables

    /// The vault review copies and isolated launches keep in memory, shared
    /// by their windows and gone when they quit.
    static let inMemory = BrowserAutofillVault(store: InMemoryCredentialKeychainStore(), servicePrefix: "memory")

    /// The vault of a private window, which keeps nothing.
    static let unavailable = BrowserAutofillVault(
        store: InMemoryCredentialKeychainStore(), servicePrefix: "private", isAvailable: false)

    // MARK: - Variables

    private let store: any CredentialKeychainStoring
    private let servicePrefix: String
    nonisolated let isAvailable: Bool

    // MARK: - Initializers

    init(store: any CredentialKeychainStoring, servicePrefix: String, isAvailable: Bool = true) {
        self.store = store
        self.servicePrefix = servicePrefix
        self.isAvailable = isAvailable
    }

    // MARK: - Actions - Reading

    func items(of kind: BrowserAutofillRecordKind) async throws -> [CredentialKeychainItem] {
        guard isAvailable else { return [] }
        return try await store.items(in: service(of: kind))
    }

    func summaries(of kind: BrowserAutofillRecordKind) async throws -> [CredentialKeychainDescriptorItem] {
        guard isAvailable else { return [] }
        return try await store.descriptorItems(in: service(of: kind))
    }

    func item(id: UUID, of kind: BrowserAutofillRecordKind) async throws -> CredentialKeychainItem? {
        guard isAvailable else { return nil }
        return try await store.item(account: id.uuidString.lowercased(), in: service(of: kind))
    }

    // MARK: - Actions - Writing

    func save(_ item: CredentialKeychainItem, of kind: BrowserAutofillRecordKind) async throws {
        guard isAvailable else { throw CredentialVaultError.unavailableInPrivateBrowsing }
        try await store.upsert(item, in: service(of: kind))
    }

    func delete(id: UUID, of kind: BrowserAutofillRecordKind) async throws {
        guard isAvailable else { return }
        try await store.delete(account: id.uuidString.lowercased(), in: service(of: kind))
    }

    private func service(of kind: BrowserAutofillRecordKind) -> String {
        "\(servicePrefix).\(kind.serviceSuffix)"
    }
}

/// Supplies the autofill vault that pairs with a credential vault, so callers
/// never type-check concrete vault conformers to choose storage.
protocol BrowserAutofillVaultProviding {
    nonisolated func makeAutofillVault() -> BrowserAutofillVault
}

extension KeychainCredentialVault: BrowserAutofillVaultProviding {
    nonisolated func makeAutofillVault() -> BrowserAutofillVault {
        BrowserAutofillVault(store: store, servicePrefix: servicePrefix)
    }
}

extension PrivateBrowsingCredentialVault: BrowserAutofillVaultProviding {
    nonisolated func makeAutofillVault() -> BrowserAutofillVault {
        .unavailable
    }
}

extension InMemoryCredentialVault: BrowserAutofillVaultProviding {
    nonisolated func makeAutofillVault() -> BrowserAutofillVault {
        .inMemory
    }
}

/// Keychain items held in memory, for launches that keep nothing.
actor InMemoryCredentialKeychainStore: CredentialKeychainStoring {
    private var services: [String: [String: CredentialKeychainItem]] = [:]

    func descriptorItems(in service: String) -> [CredentialKeychainDescriptorItem] {
        services[service, default: [:]].values.map {
            CredentialKeychainDescriptorItem(
                account: $0.account, metadata: $0.metadata, isSynchronizable: $0.isSynchronizable)
        }
    }

    func items(in service: String) -> [CredentialKeychainItem] {
        Array(services[service, default: [:]].values)
    }

    func item(account: String, in service: String) -> CredentialKeychainItem? {
        services[service]?[account]
    }

    func upsert(_ item: CredentialKeychainItem, in service: String) {
        services[service, default: [:]][item.account] = item
    }

    func delete(account: String, in service: String) {
        services[service]?[account] = nil
    }

    func deleteAll(in service: String) {
        services[service] = nil
    }
}

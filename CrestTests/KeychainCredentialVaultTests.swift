import Foundation
import XCTest

@testable import Crest

@MainActor
final class KeychainCredentialVaultTests: XCTestCase {
    func testSynchronizationMigrationRollsBackEarlierItemsWhenALaterWriteFails() async throws {
        let spaceID = SpaceID()
        let first = try keychainItem(
            descriptor: descriptor(
                id: CredentialID(rawValue: UUID()),
                spaceID: spaceID,
                username: "first"
            ),
            password: "first-secret"
        )
        let second = try keychainItem(
            descriptor: descriptor(
                id: CredentialID(rawValue: UUID()),
                spaceID: spaceID,
                username: "second"
            ),
            password: "second-secret"
        )
        let store = FailingMigrationCredentialKeychainStore(
            items: [first, second],
            failingAccount: second.account
        )
        let vault = KeychainCredentialVault(
            store: store,
            servicePrefix: "test.crest"
        )

        do {
            try await vault.setSynchronizable(true, in: spaceID)
            XCTFail("Expected the second migration write to fail")
        } catch {
            XCTAssertEqual(error as? TestCredentialKeychainError, .injectedFailure)
        }

        let storedItems = await store.storedItems
        let writes = await store.writes
        XCTAssertEqual(storedItems, [first, second])
        XCTAssertEqual(writes.map(\.account), [first.account, second.account, first.account])
        XCTAssertEqual(writes.map(\.isSynchronizable), [true, true, false])
    }

    func testCredentialLookupRejectsNonUTF8SecretData() async throws {
        let spaceID = SpaceID()
        let descriptor = descriptor(
            id: CredentialID(rawValue: UUID()),
            spaceID: spaceID,
            username: "person"
        )
        var item = try keychainItem(descriptor: descriptor, password: "secret")
        item = CredentialKeychainItem(
            account: item.account,
            metadata: item.metadata,
            secret: Data([0xFF]),
            isSynchronizable: item.isSynchronizable
        )
        let store = FailingMigrationCredentialKeychainStore(items: [item])
        let vault = KeychainCredentialVault(
            store: store,
            servicePrefix: "test.crest"
        )

        do {
            _ = try await vault.credential(id: descriptor.id, in: spaceID)
            XCTFail("Expected malformed password data to fail closed")
        } catch {
            XCTAssertEqual(error as? CredentialVaultError, .malformedStoredCredential)
        }
    }

    func testDescriptorLookupRejectsMetadataWhoseSyncFlagDiffersFromKeychain() async throws {
        let spaceID = SpaceID()
        let descriptor = descriptor(
            id: CredentialID(rawValue: UUID()),
            spaceID: spaceID,
            username: "person"
        )
        let encoded = try JSONEncoder().encode(descriptor)
        let item = CredentialKeychainItem(
            account: descriptor.id.rawValue.uuidString.lowercased(),
            metadata: encoded,
            secret: Data("secret".utf8),
            isSynchronizable: true
        )
        let store = FailingMigrationCredentialKeychainStore(items: [item])
        let vault = KeychainCredentialVault(
            store: store,
            servicePrefix: "test.crest"
        )

        do {
            _ = try await vault.descriptors(in: spaceID)
            XCTFail("Expected inconsistent Keychain metadata to fail closed")
        } catch {
            XCTAssertEqual(error as? CredentialVaultError, .malformedStoredCredential)
        }
    }

    func testAtomicReplacementRestoresTheOriginalInventoryWhenAWriteFails() async throws {
        let spaceID = SpaceID()
        let firstDescriptor = descriptor(
            id: CredentialID(rawValue: UUID()),
            spaceID: spaceID,
            username: "first"
        )
        let secondDescriptor = descriptor(
            id: CredentialID(rawValue: UUID()),
            spaceID: spaceID,
            username: "second"
        )
        let first = try keychainItem(
            descriptor: firstDescriptor,
            password: "first-original"
        )
        let second = try keychainItem(
            descriptor: secondDescriptor,
            password: "second-original"
        )
        let store = FailingMigrationCredentialKeychainStore(
            items: [first, second],
            failingAccount: second.account
        )
        let vault = KeychainCredentialVault(
            store: store,
            servicePrefix: "test.crest"
        )
        var synchronizedFirst = firstDescriptor
        synchronizedFirst.isSynchronizable = true
        var synchronizedSecond = secondDescriptor
        synchronizedSecond.isSynchronizable = true

        do {
            try await vault.replaceAll(
                [
                    BrowserCredential(
                        descriptor: synchronizedFirst,
                        password: "first-replacement"
                    ),
                    BrowserCredential(
                        descriptor: synchronizedSecond,
                        password: "second-replacement"
                    ),
                ],
                in: spaceID
            )
            XCTFail("Expected the replacement write to fail")
        } catch {
            XCTAssertEqual(error as? TestCredentialKeychainError, .injectedFailure)
        }

        let restoredItems = await store.storedItems
        XCTAssertEqual(restoredItems, [first, second])
    }

    private func descriptor(
        id: CredentialID,
        spaceID: SpaceID,
        username: String
    ) -> CredentialDescriptor {
        CredentialDescriptor(
            id: id,
            spaceID: spaceID,
            origin: CredentialOrigin(
                securityProtocol: "https",
                host: "example.com",
                port: 443
            )!,
            username: username,
            createdAt: Date(timeIntervalSince1970: 1_000),
            isSynchronizable: false
        )
    }

    private func keychainItem(
        descriptor: CredentialDescriptor,
        password: String
    ) throws -> CredentialKeychainItem {
        CredentialKeychainItem(
            account: descriptor.id.rawValue.uuidString.lowercased(),
            metadata: try JSONEncoder().encode(descriptor),
            secret: Data(password.utf8),
            isSynchronizable: descriptor.isSynchronizable
        )
    }
}

private enum TestCredentialKeychainError: Error, Equatable {
    case injectedFailure
}

private actor FailingMigrationCredentialKeychainStore: CredentialKeychainStoring {
    private var itemsByAccount: [String: CredentialKeychainItem]
    private let accountOrder: [String]
    private let failingAccount: String?
    private var hasInjectedFailure = false
    private(set) var writes: [CredentialKeychainItem] = []

    init(
        items: [CredentialKeychainItem],
        failingAccount: String? = nil
    ) {
        itemsByAccount = Dictionary(
            uniqueKeysWithValues: items.map { ($0.account, $0) }
        )
        accountOrder = items.map(\.account)
        self.failingAccount = failingAccount
    }

    var storedItems: [CredentialKeychainItem] {
        accountOrder.compactMap { itemsByAccount[$0] }
    }

    func descriptorItems(in _: String) -> [CredentialKeychainDescriptorItem] {
        storedItems.map {
            CredentialKeychainDescriptorItem(
                account: $0.account,
                metadata: $0.metadata,
                isSynchronizable: $0.isSynchronizable
            )
        }
    }

    func items(in _: String) -> [CredentialKeychainItem] { storedItems }

    func item(
        account: String,
        in _: String
    ) -> CredentialKeychainItem? {
        itemsByAccount[account]
    }

    func upsert(_ item: CredentialKeychainItem, in _: String) throws {
        writes.append(item)
        if item.account == failingAccount,
            item.isSynchronizable,
            !hasInjectedFailure
        {
            hasInjectedFailure = true
            throw TestCredentialKeychainError.injectedFailure
        }
        itemsByAccount[item.account] = item
    }

    func delete(account: String, in _: String) {
        itemsByAccount[account] = nil
    }

    func deleteAll(in _: String) {
        itemsByAccount.removeAll()
    }
}

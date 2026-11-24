import Foundation

actor InMemoryCredentialVault: CredentialVault {
    private var credentialsBySpace: [UUID: [UUID: BrowserCredential]] = [:]
    private var extrasBySpace: [UUID: [UUID: BrowserCredentialExtras]] = [:]

    func descriptors(in spaceID: UUID) -> [CredentialDescriptor] {
        sortedDescriptors(
            credentialsBySpace[spaceID, default: [:]].values.map(\.descriptor)
        )
    }

    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: UUID
    ) -> [CredentialDescriptor] {
        sortedDescriptors(
            credentialsBySpace[spaceID, default: [:]].values
                .filter {
                    $0.descriptor.origins.contains(origin)
                        && $0.descriptor.scope == .webForm
                }
                .map(\.descriptor)
        )
    }

    func inventory(in spaceID: UUID) -> CredentialInventory {
        CredentialInventory(
            descriptors: descriptors(in: spaceID), unreadableCount: 0,
            extras: extrasBySpace[spaceID, default: [:]].mapValues(\.summary))
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) -> [CredentialDescriptor] {
        sortedDescriptors(
            credentialsBySpace[spaceID, default: [:]].values
                .filter {
                    $0.descriptor.origin == protectionSpace.origin
                        && $0.descriptor.scope == protectionSpace.credentialScope
                }
                .map(\.descriptor)
        )
    }

    /// Every credential this vault holds reads back.
    func unreadableCredentialCount(in spaceID: UUID) -> Int {
        0
    }

    func credential(id: UUID, in spaceID: UUID) -> BrowserCredential? {
        credentialsBySpace[spaceID]?[id]
    }

    func save(_ credential: BrowserCredential, in spaceID: UUID) throws {
        guard credential.descriptor.spaceID == spaceID else {
            throw CredentialVaultError.spaceMismatch(
                expected: spaceID,
                actual: credential.descriptor.spaceID
            )
        }
        credentialsBySpace[spaceID, default: [:]][credential.descriptor.id] = credential
    }

    func replaceAll(_ credentials: [BrowserCredential], in spaceID: UUID) throws {
        for credential in credentials where credential.descriptor.spaceID != spaceID {
            throw CredentialVaultError.spaceMismatch(
                expected: spaceID,
                actual: credential.descriptor.spaceID
            )
        }
        credentialsBySpace[spaceID] = Dictionary(
            uniqueKeysWithValues: credentials.map { ($0.descriptor.id, $0) }
        )
        extrasBySpace[spaceID] = extrasBySpace[spaceID]?.filter { credentialsBySpace[spaceID]?[$0.key] != nil }
    }

    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: UUID) {
        guard var credentials = credentialsBySpace[spaceID] else { return }
        for id in credentials.keys {
            credentials[id]?.descriptor.isSynchronizable = isSynchronizable
        }
        credentialsBySpace[spaceID] = credentials
    }

    func delete(id: UUID, in spaceID: UUID) {
        credentialsBySpace[spaceID]?[id] = nil
        extrasBySpace[spaceID]?[id] = nil
        if credentialsBySpace[spaceID]?.isEmpty == true {
            credentialsBySpace[spaceID] = nil
        }
    }

    func deleteAll(in spaceID: UUID) {
        credentialsBySpace[spaceID] = nil
        extrasBySpace[spaceID] = nil
    }

    func deleteUnreadableCredentials(in spaceID: UUID) {}

    func extras(id: UUID, in spaceID: UUID) -> BrowserCredentialExtras? {
        extrasBySpace[spaceID]?[id]
    }

    func saveExtras(_ extras: BrowserCredentialExtras, for descriptor: CredentialDescriptor, in spaceID: UUID) throws {
        guard credentialsBySpace[spaceID]?[descriptor.id] != nil else {
            throw CredentialVaultError.missingCredential
        }
        extrasBySpace[spaceID, default: [:]][descriptor.id] = extras.isEmpty ? nil : extras
    }

    private func sortedDescriptors(_ descriptors: [CredentialDescriptor]) -> [CredentialDescriptor] {
        descriptors.sorted {
            let usernameOrder = $0.username.localizedCaseInsensitiveCompare($1.username)
            if usernameOrder != .orderedSame {
                return usernameOrder == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

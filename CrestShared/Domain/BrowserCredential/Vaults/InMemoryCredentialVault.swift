import Foundation

actor InMemoryCredentialVault: CredentialVault {
    private var credentialsBySpace: [SpaceID: [CredentialID: BrowserCredential]] = [:]

    func descriptors(in spaceID: SpaceID) -> [CredentialDescriptor] {
        sortedDescriptors(
            credentialsBySpace[spaceID, default: [:]].values.map(\.descriptor)
        )
    }

    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: SpaceID
    ) -> [CredentialDescriptor] {
        sortedDescriptors(
            credentialsBySpace[spaceID, default: [:]].values
                .filter {
                    $0.descriptor.origin == origin
                        && $0.descriptor.scope == .webForm
                }
                .map(\.descriptor)
        )
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: SpaceID
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

    func credential(id: CredentialID, in spaceID: SpaceID) -> BrowserCredential? {
        credentialsBySpace[spaceID]?[id]
    }

    func save(_ credential: BrowserCredential, in spaceID: SpaceID) throws {
        guard credential.descriptor.spaceID == spaceID else {
            throw CredentialVaultError.spaceMismatch(
                expected: spaceID,
                actual: credential.descriptor.spaceID
            )
        }
        credentialsBySpace[spaceID, default: [:]][credential.descriptor.id] = credential
    }

    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: SpaceID) {
        guard var credentials = credentialsBySpace[spaceID] else { return }
        for id in credentials.keys {
            credentials[id]?.descriptor.isSynchronizable = isSynchronizable
        }
        credentialsBySpace[spaceID] = credentials
    }

    func delete(id: CredentialID, in spaceID: SpaceID) {
        credentialsBySpace[spaceID]?[id] = nil
        if credentialsBySpace[spaceID]?.isEmpty == true {
            credentialsBySpace[spaceID] = nil
        }
    }

    func deleteAll(in spaceID: SpaceID) {
        credentialsBySpace[spaceID] = nil
    }

    private func sortedDescriptors(_ descriptors: [CredentialDescriptor]) -> [CredentialDescriptor] {
        descriptors.sorted {
            let usernameOrder = $0.username.localizedCaseInsensitiveCompare($1.username)
            if usernameOrder != .orderedSame {
                return usernameOrder == .orderedAscending
            }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }
}

struct BrowserCredentialDetailRequest: Equatable, Identifiable, Sendable {
    let descriptor: CredentialDescriptor
    let spaceAssignment: BrowserSpaceRuntimeAssignment
    let spaceName: String

    var id: BrowserCredentialDetailPresentationIdentity {
        BrowserCredentialDetailPresentationIdentity(
            credentialID: descriptor.id,
            spaceAssignment: spaceAssignment
        )
    }

    init(
        descriptor: CredentialDescriptor,
        spaceAssignment: BrowserSpaceRuntimeAssignment,
        spaceName: String
    ) {
        self.descriptor = descriptor
        self.spaceAssignment = spaceAssignment
        self.spaceName = spaceName
    }

    init?(descriptor: CredentialDescriptor, space: BrowserSpace) {
        guard descriptor.spaceID == space.id else { return nil }
        self.init(
            descriptor: descriptor,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: space),
            spaceName: space.name
        )
    }
}

struct BrowserCredentialDetailPresentationIdentity: Equatable, Hashable, Sendable {
    let credentialID: CredentialID
    let spaceAssignment: BrowserSpaceRuntimeAssignment
}

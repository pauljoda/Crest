import Foundation

struct BrowserCredentialDetailRequest: Equatable, Identifiable, Sendable {
    let descriptor: CredentialDescriptor
    let spaceAssignment: BrowserSpaceRuntimeAssignment
    let spaceName: String
    /// Whether the login keeps notes, as the list read it.
    var hasNotes = false
    /// Whether the login makes one-time codes, as the list read it.
    var hasCode = false
    /// What the core found wrong with the login's password.
    var concerns: [PasswordConcern] = []

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

    @MainActor
    init?(
        descriptor: CredentialDescriptor, space: SpaceModel, extras: BrowserCredentialExtrasSummary? = nil,
        concerns: [PasswordConcern] = []
    ) {
        guard descriptor.spaceID == space.id else { return nil }
        self.init(
            descriptor: descriptor,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: space),
            spaceName: space.settings.name
        )
        hasNotes = extras?.hasNotes == true
        hasCode = extras?.hasCode == true
        self.concerns = concerns
    }
}

struct BrowserCredentialDetailPresentationIdentity: Equatable, Hashable, Sendable {
    let credentialID: UUID
    let spaceAssignment: BrowserSpaceRuntimeAssignment
}

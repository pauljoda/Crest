import Foundation

/// What a saved login says about itself, without its password: where it signs
/// in, as whom, and when it was saved, changed and used. `sites` are the other
/// sites the person added to the login, beside the one it was saved for, and
/// `passwordChangedAt` is when its password last changed. Both are keys older
/// builds ignore.
struct CredentialDescriptor: Codable, Equatable, Identifiable, Sendable {
    // MARK: - Static Variables

    /// The most sites one login names beside the one it was saved for.
    static let maximumSites = 24

    // MARK: - Variables

    let id: UUID
    let spaceID: UUID
    let origin: CredentialOrigin
    var scope: BrowserCredentialScope
    var username: String
    var displayName: String?
    let createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var isSynchronizable: Bool
    var sites: [CredentialOrigin]
    var passwordChangedAt: Date?

    /// Every site the login signs in to: the one it was saved for, then the
    /// ones the person added.
    var origins: [CredentialOrigin] { [origin] + sites.filter { $0 != origin } }

    // MARK: - Initializers

    init(
        id: UUID = UUID(),
        spaceID: UUID,
        origin: CredentialOrigin,
        scope: BrowserCredentialScope = .webForm,
        username: String,
        displayName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        isSynchronizable: Bool = false,
        sites: [CredentialOrigin] = [],
        passwordChangedAt: Date? = nil
    ) {
        self.id = id
        self.spaceID = spaceID
        self.origin = origin
        self.scope = scope
        self.username = username
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastUsedAt = lastUsedAt
        self.isSynchronizable = isSynchronizable
        self.sites = sites
        self.passwordChangedAt = passwordChangedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case spaceID
        case origin
        case scope
        case username
        case displayName
        case createdAt
        case updatedAt
        case lastUsedAt
        case isSynchronizable
        case sites
        case passwordChangedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIdentity(forKey: .id)
        spaceID = try container.decodeIdentity(forKey: .spaceID)
        origin = try container.decode(CredentialOrigin.self, forKey: .origin)
        scope =
            try container.decodeIfPresent(BrowserCredentialScope.self, forKey: .scope)
            ?? .webForm
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        isSynchronizable = try container.decode(Bool.self, forKey: .isSynchronizable)
        // A site that no longer decodes is dropped rather than losing the login.
        sites =
            ((try? container.decodeIfPresent([FailableCredentialOrigin].self, forKey: .sites)) ?? [])
            .compactMap(\.origin).prefix(Self.maximumSites).map(\.self)
        passwordChangedAt = try container.decodeIfPresent(Date.self, forKey: .passwordChangedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Descriptors keep the identity spelling every earlier build wrote.
        try container.encodeStoredIdentity(id, forKey: .id)
        // Synchronizable descriptors reach older builds on other devices,
        // which read only the stored spelling, so it stays for good.
        try container.encodeStoredIdentity(spaceID, forKey: .spaceID)
        try container.encode(origin, forKey: .origin)
        try container.encode(scope, forKey: .scope)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(isSynchronizable, forKey: .isSynchronizable)
        if !sites.isEmpty { try container.encode(sites, forKey: .sites) }
        try container.encodeIfPresent(passwordChangedAt, forKey: .passwordChangedAt)
    }
}

// MARK: - Types

/// One stored site, or nil when it no longer decodes.
private struct FailableCredentialOrigin: Decodable {
    let origin: CredentialOrigin?

    init(from decoder: Decoder) throws {
        origin = try? CredentialOrigin(from: decoder)
    }
}

import Foundation

// MARK: - Types

/// The fields a fill writes into, by the index the page script reads them
/// with: the visible username field and the current password field for a
/// saved login, and every new password field for one Crest makes.
struct BrowserCredentialFillFields: Equatable, Sendable {
    static let none = BrowserCredentialFillFields(username: nil, password: nil, newPasswords: [])

    let username: Int?
    let password: Int?
    let newPasswords: [Int]
}

struct BrowserCredentialFillRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let origin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let usernameHint: String?
    let passwordKind: CredentialPasswordKind
    let isCrossOriginFrame: Bool
    let requestedAt: Date

    /// Where the field that asked sits in the page's viewport, in CSS pixels,
    /// or `nil` where nothing can be said about it.
    ///
    /// Only a main-frame field ever fills this in. A subframe reports its rect
    /// in its own viewport, and a cross-origin one cannot know where that
    /// viewport lands in the page — so a prompt raised from a frame keeps the
    /// placement it has always had rather than pointing at the wrong place.
    let fieldRect: BrowserCredentialFieldRect?

    /// The fields the core chose for the fill.
    let fields: BrowserCredentialFillFields

    /// Whether the prompt shows only when the Space has logins for the site,
    /// as a username field's does.
    let isQuietWithoutLogins: Bool

    /// What the site asks of a password Crest makes for the new password field.
    let requirements: PasswordRequirements

    init(
        id: UUID,
        origin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        usernameHint: String?,
        passwordKind: CredentialPasswordKind,
        isCrossOriginFrame: Bool,
        requestedAt: Date,
        fieldRect: BrowserCredentialFieldRect? = nil,
        fields: BrowserCredentialFillFields = .none,
        isQuietWithoutLogins: Bool = false,
        requirements: PasswordRequirements = .none
    ) {
        self.id = id
        self.origin = origin
        self.topLevelOrigin = topLevelOrigin
        self.usernameHint = usernameHint
        self.passwordKind = passwordKind
        self.isCrossOriginFrame = isCrossOriginFrame
        self.requestedAt = requestedAt
        self.fieldRect = fieldRect
        self.fields = fields
        self.isQuietWithoutLogins = isQuietWithoutLogins
        self.requirements = requirements
    }

    /// The same request, following its field to where the page just moved it.
    ///
    /// Everything the prompt is identified and guarded by — its ID above all —
    /// is carried through unchanged, so a scroll moves the panel without
    /// re-asking the vault or re-arming any of the fill guards.
    func following(_ fieldRect: BrowserCredentialFieldRect) -> Self {
        BrowserCredentialFillRequest(
            id: id,
            origin: origin,
            topLevelOrigin: topLevelOrigin,
            usernameHint: usernameHint,
            passwordKind: passwordKind,
            isCrossOriginFrame: isCrossOriginFrame,
            requestedAt: requestedAt,
            fieldRect: fieldRect,
            fields: fields,
            isQuietWithoutLogins: isQuietWithoutLogins,
            requirements: requirements
        )
    }
}

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

/// One value a fill writes: the field, by the index the page script reads
/// it with, and what goes in it, a select's option value for a select.
struct BrowserAutofillValue: Equatable, Sendable, CustomStringConvertible {
    let field: Int
    let value: String

    var description: String { "BrowserAutofillValue(field: \(field), value: <redacted>)" }
}

/// What an address or card fill needs from the page: the section the core
/// read around the focused field, and the form's fields the core plans the
/// fill over.
struct BrowserAutofillOffer: Equatable, Sendable {
    let section: AutofillSection
    let fields: [FormField]
    let focused: Int

    /// Whether the section takes a payment card rather than an address.
    var takesCard: Bool { section.kind == .card }
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
    /// A main-frame field fills this in, and so does a field in a frame the
    /// top page can reach, which adds its frames' places in the page. A
    /// cross-origin frame cannot know where its viewport lands in the page, so
    /// a prompt raised from one keeps its own placement rather than pointing at
    /// the wrong place.
    let fieldRect: BrowserCredentialFieldRect?

    /// The fields the core chose for the fill.
    let fields: BrowserCredentialFillFields

    /// Whether the prompt shows only when the Space has logins for the site,
    /// as a username field's does.
    let isQuietWithoutLogins: Bool

    /// What the site asks of a password Crest makes for the new password field.
    let requirements: PasswordRequirements

    /// The fields a one-time code goes into, for a request from a field that
    /// takes one, which offers codes rather than a password.
    let codeFields: OneTimeCodeFields?

    /// The address or card section a request from one of its fields offers.
    let autofill: BrowserAutofillOffer?

    /// The login the person chose on the username step just before this
    /// password step, which fills by itself instead of being offered.
    let chosenCredentialID: UUID?

    /// Whether a saved login fills the request: one from a sign-in form's
    /// username or current password field, never a new password, a code, an
    /// address or a card.
    var takesSavedLogin: Bool {
        passwordKind == .current && codeFields == nil && autofill == nil
            && (fields.username != nil || fields.password != nil)
    }

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
        requirements: PasswordRequirements = .none,
        codeFields: OneTimeCodeFields? = nil,
        autofill: BrowserAutofillOffer? = nil,
        chosenCredentialID: UUID? = nil
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
        self.codeFields = codeFields
        self.autofill = autofill
        self.chosenCredentialID = chosenCredentialID
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
            requirements: requirements,
            codeFields: codeFields,
            autofill: autofill,
            chosenCredentialID: chosenCredentialID
        )
    }
}

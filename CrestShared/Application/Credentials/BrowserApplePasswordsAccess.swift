import Foundation

/// What shared code may ask of Apple Passwords. Only the Mac implements it, and
/// every other platform leaves a store's access nil, so nothing here is
/// reachable from CrestMobile.
///
/// The Mac's implementation always gets its `ApplePasswordsSupport` from the
/// core's `ApplePasswordsAvailability` query. Shared code reads the core's
/// answer (`startsHelper`, `offersApplePasswords`, `needsPairing`) and never
/// reaches the helper or an engine itself.
@MainActor
protocol BrowserApplePasswordsAccess: AnyObject {
    /// The core's answer for a Space now; nil when the core cannot answer.
    func support(
        for space: BrowserSpaceIdentity, preferences: CredentialPreferences, isPrivateBrowsing: Bool
    ) -> ApplePasswordsSupport?

    /// Whether this launch could start the helper for a Space that turned
    /// Apple Passwords on, whatever the Space chose.
    func couldStartHelper(
        for space: BrowserSpaceIdentity, preferences: CredentialPreferences, isPrivateBrowsing: Bool
    ) -> Bool

    /// Starts the helper when `support` starts it. Asks only for what the
    /// helper supports and shows the person nothing.
    func start(support: ApplePasswordsSupport) async

    /// Has the helper show a pairing code in its own window.
    func requestPairingCode(support: ApplePasswordsSupport) async -> BrowserApplePasswordsPairingOutcome

    /// Pairs with the code the person read from the helper's window.
    func completePairing(code: String, support: ApplePasswordsSupport) async -> BrowserApplePasswordsPairingOutcome

    /// The person gave up on the code the helper shows. Does nothing when no code is waiting.
    func cancelPairing() async

    /// Whether the helper can save an account that has no username.
    var savesAccountsWithoutUsername: Bool { get }

    /// Offers the candidate to Apple Passwords, for the origin it was captured
    /// for. The result is "sent": Apple's own alert asks the person to confirm,
    /// and Crest cannot tell whether they did.
    /// - Parameter tab: The tab of the page that asked, where there is one.
    /// - Throws: When the helper cannot take the offer; nothing was sent.
    func save(_ candidate: BrowserCredentialSaveCandidate, tab: UUID?, support: ApplePasswordsSupport) async throws

    /// The suggestions for the origin in the tab that asked. They are issued by
    /// Apple Passwords' own vault, which serves suggestions and reads only;
    /// saving goes through `save`.
    func descriptors(
        matching origin: CredentialOrigin, in spaceID: UUID, tab: UUID?
    ) async throws -> [CredentialDescriptor]

    /// The saved account a row stands for, read for the tab that picked it, and
    /// only for a row this access issued.
    func credential(id: UUID, in spaceID: UUID, tab: UUID?) async throws -> BrowserCredential?

    /// What Apple says about saving passwords for the origin's site. A lookup
    /// that fails for any reason is `unknown`, never `notNever`.
    func neverSaves(
        for origin: CredentialOrigin, tab: UUID?, support: ApplePasswordsSupport
    ) async -> ApplePasswordsNeverSaveAnswer

    /// Has the helper open Apple's Passwords app on the origin's site. Needs
    /// the helper running but no pairing.
    /// - Throws: When the helper cannot take the request; nothing was sent.
    func openPasswordsApp(for origin: CredentialOrigin, support: ApplePasswordsSupport) async throws

    /// Whether the paired helper says it fills one-time codes.
    var canFillOneTimeCodes: Bool { get }

    /// Lists the one-time codes for a frame: its origin, then the top-level
    /// page's. Rows replace those the same tab was issued before and live in
    /// memory until the next listing, a fill, `forgetOneTimeCodes`, or the
    /// helper unpairing. The values stay inside until a row is picked.
    /// - Throws: Unless the frame's origin is https, the core's answer allows
    ///   the helper and the helper said it fills codes.
    func oneTimeCodes(
        for origin: CredentialOrigin, topLevelOrigin: CredentialOrigin, in spaceID: UUID, username: String?,
        tab: UUID?, support: ApplePasswordsSupport
    ) async throws -> [BrowserOneTimeCodeSuggestion]

    /// The code to fill for a row this access issued to this tab, only for the
    /// frame and top-level origins it was issued for, only within two minutes
    /// of the listing, and only once. A generated code is read from the helper now.
    func oneTimeCode(
        for suggestionID: UUID, origin: CredentialOrigin, topLevelOrigin: CredentialOrigin, in spaceID: UUID,
        tab: UUID?, support: ApplePasswordsSupport
    ) async throws -> String

    /// Forgets the one-time code rows issued to the tab.
    func forgetOneTimeCodes(tab: UUID?)

    /// Counts the helper's announcements that a one-time code arrived, so an
    /// open code list can look again. Observable.
    var oneTimeCodeArrivals: Int { get }

    /// Apple Passwords' rows were just shown in the Space, so the Space may
    /// also be told about Apple's own extension.
    func rowsWereShown(support: ApplePasswordsSupport, in space: BrowserSpaceIdentity)

    /// Turns Apple's extension off in the Space.
    func turnOffExtension(in space: BrowserSpaceIdentity)
}

/// Whether Apple marks a site never-save.
enum ApplePasswordsNeverSaveAnswer: Equatable, Sendable {
    /// Apple marks the site never-save.
    case neverSaves
    /// Apple answered and does not mark it.
    case notNever
    /// The lookup failed or was not answered, so nothing is known.
    case unknown
}

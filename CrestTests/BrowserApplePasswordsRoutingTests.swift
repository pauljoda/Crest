import Foundation
import XCTest

@testable import Crest

/// A row fills only through the vault that issued it, and Apple Passwords'
/// rows stay out of everything that is not a suggestion.
@MainActor
final class BrowserApplePasswordsRoutingTests: XCTestCase {
    private let origin = CredentialOrigin(scheme: "https", host: "accounts.crest.test", port: 443)

    func testARowFillsOnlyThroughTheVaultThatIssuedItAndAppleRowsStayOutOfSavedPasswords() async throws {
        var seed = SessionState.Seed.preview
        seed.spaces[0].settings.credentialPreferences = Self.preferences(usesApplePasswords: true)
        let space = seed.spaces[0]
        let crestVault = InMemoryCredentialVault()
        let store = BrowserStore(seed: seed, credentialVault: crestVault)
        let source = FakeAppleSource(logins: ["apple-user"], password: "apple-secret")
        store.applePasswords = FakeAppleAccess(core: store.core, source: source)
        let crest = BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: space.id, origin: origin, username: "crest-user",
                createdAt: Date(timeIntervalSince1970: 1_000)),
            password: "crest-secret")
        try await crestVault.save(crest, in: space.id)

        let offer = try await store.credentialOffer(for: origin, in: space.id, tab: nil)
        let apple = try XCTUnwrap(offer.suggestions.first { $0.provider == .applePasswords })
        let ownRow = try XCTUnwrap(offer.suggestions.first { $0.provider == .crestPasswords })
        XCTAssertEqual(apple.descriptor.username, "apple-user")
        XCTAssertEqual(ownRow.descriptor.id, crest.descriptor.id)

        let appleFill = try await store.credential(for: apple, in: space.id, tab: nil)
        let crestFill = try await store.credential(for: ownRow, in: space.id, tab: nil)
        XCTAssertEqual(appleFill?.password, "apple-secret")
        XCTAssertEqual(crestFill?.password, "crest-secret")

        // An identifier the other vault never issued reads nothing.
        let readsBefore = source.passwordReads
        let crestIDAsApple = BrowserCredentialSuggestion(descriptor: crest.descriptor, provider: .applePasswords)
        let appleIDAsCrest = BrowserCredentialSuggestion(descriptor: apple.descriptor, provider: .crestPasswords)
        let crestAsApple = try await store.credential(for: crestIDAsApple, in: space.id, tab: nil)
        let appleAsCrest = try await store.credential(for: appleIDAsCrest, in: space.id, tab: nil)
        XCTAssertNil(crestAsApple)
        XCTAssertNil(appleAsCrest)
        XCTAssertEqual(source.passwordReads, readsBefore)

        // Apple Passwords' rows are not saved passwords and never match a save.
        let saved = try await store.savedCredentialDescriptors(in: space.id)
        XCTAssertEqual(saved.map(\.id), [crest.descriptor.id])
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(), origin: origin, topLevelOrigin: origin, username: "apple-user", password: "apple-secret",
            passwordKind: .current, isCrossOriginFrame: false, submittedAt: .now)
        let plan = try await store.credentialSavePlan(for: candidate, in: space.id)
        XCTAssertTrue(plan is BrowserCredentialCreatePlan)
    }

    func testAPrivateWindowNeverListsApplePasswordsRows() async throws {
        let store = BrowserStore.privateBrowsing(core: .hostingPages())
        let spaceID = try XCTUnwrap(store.shownSpace?.id)
        let source = FakeAppleSource(logins: ["apple-user"], password: "apple-secret")
        store.applePasswords = FakeAppleAccess(core: store.core, source: source)
        store.updateCredentialPreferences(Self.preferences(usesApplePasswords: true), in: spaceID)
        XCTAssertEqual(store.shownSpace?.settings.credentialPreferences.usesApplePasswords, true)

        let offer = try await store.credentialOffer(for: origin, in: spaceID, tab: nil)

        XCTAssertTrue(offer.suggestions.isEmpty)
        XCTAssertFalse(offer.offersApplePasswordsPairing)
        XCTAssertEqual(source.loginReads, 0)
    }

    func testASaveGoesToAppleByDefaultAndToCrestOnlyWhenChosen() async throws {
        var seed = SessionState.Seed.preview
        seed.spaces[0].settings.credentialPreferences = Self.preferences(usesApplePasswords: true)
        let space = seed.spaces[0]
        let crestVault = InMemoryCredentialVault()
        let store = BrowserStore(seed: seed, credentialVault: crestVault)
        let access = FakeAppleAccess(core: store.core, source: FakeAppleSource(logins: [], password: ""))
        store.applePasswords = access
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(), origin: origin, topLevelOrigin: origin, username: "ada", password: "secret",
            passwordKind: .new, isCrossOriginFrame: false, submittedAt: .now)

        // Apple Passwords is the default: it gets the offer, and Crest's vault is not written.
        let toApple = BrowserCredentialSavePromptModel()
        await toApple.prepare(candidate: candidate, in: space.id, tab: nil, browser: store)
        XCTAssertEqual(toApple.destination, .applePasswords)
        XCTAssertEqual(toApple.alternateDestination, .crestPasswords)
        await toApple.commit(candidate: candidate, in: space.id, tab: nil, browser: store)
        XCTAssertEqual(toApple.phase, .sent)
        XCTAssertEqual(access.saved.map(\.origin), [origin])
        XCTAssertEqual(access.saved.map(\.username), ["ada"])
        let afterApple = try await crestVault.descriptors(in: space.id)
        XCTAssertTrue(afterApple.isEmpty)

        // Choosing Crest for this save writes the vault and sends Apple nothing more.
        let toCrest = BrowserCredentialSavePromptModel()
        await toCrest.prepare(candidate: candidate, in: space.id, tab: nil, browser: store)
        toCrest.choose(.crestPasswords)
        XCTAssertEqual(toCrest.destination, .crestPasswords)
        await toCrest.commit(candidate: candidate, in: space.id, tab: nil, browser: store)
        XCTAssertEqual(toCrest.phase, .saved(.created))
        XCTAssertEqual(access.saved.count, 1)
        let afterCrest = try await crestVault.descriptors(in: space.id)
        XCTAssertEqual(afterCrest.map(\.username), ["ada"])
    }

    func testAGeneratedPasswordGoesToAppleFirstAndOnlyFallsBackToCrestWhenItCannot() async throws {
        var seed = SessionState.Seed.preview
        seed.spaces[0].settings.credentialPreferences = Self.preferences(usesApplePasswords: true)
        let space = seed.spaces[0]
        func candidate(username: String) -> BrowserCredentialSaveCandidate {
            BrowserCredentialSaveCandidate(
                id: UUID(), origin: origin, topLevelOrigin: origin, username: username, password: "generated",
                passwordKind: .new, isCrossOriginFrame: false, submittedAt: .now)
        }
        let source = FakeAppleSource(logins: [], password: "")

        // Apple takes it: one send, nothing in Crest's vault.
        let sentVault = InMemoryCredentialVault()
        let sent = BrowserStore(seed: seed, credentialVault: sentVault)
        let accepting = FakeAppleAccess(core: sent.core, source: source)
        sent.applePasswords = accepting
        let wasSent = try await sent.keepGeneratedPassword(candidate(username: "ada"), in: space.id, tab: nil)
        XCTAssertTrue(wasSent)
        XCTAssertEqual(accepting.saved.count, 1)
        let sentDescriptors = try await sentVault.descriptors(in: space.id)
        XCTAssertTrue(sentDescriptors.isEmpty)

        // The send fails: Crest keeps the password.
        let failedVault = InMemoryCredentialVault()
        let failing = BrowserStore(seed: seed, credentialVault: failedVault)
        let refusing = FakeAppleAccess(core: failing.core, source: source, sendFails: true)
        failing.applePasswords = refusing
        let wasSentAfterFailure = try await failing.keepGeneratedPassword(
            candidate(username: "ada"), in: space.id, tab: nil)
        XCTAssertFalse(wasSentAfterFailure)
        let failedDescriptors = try await failedVault.descriptors(in: space.id)
        XCTAssertEqual(failedDescriptors.map(\.username), ["ada"])

        // No username, and the helper cannot save one without: Apple gets nothing. Crest's own
        // vault does not keep a password without a username either (the core refuses it), so
        // the save fails and the flow stops before filling. The password is never used, so
        // none is lost.
        let anonymousVault = InMemoryCredentialVault()
        let anonymous = BrowserStore(seed: seed, credentialVault: anonymousVault)
        let incapable = FakeAppleAccess(core: anonymous.core, source: source, savesAccountsWithoutUsername: false)
        anonymous.applePasswords = incapable
        do {
            _ = try await anonymous.keepGeneratedPassword(candidate(username: ""), in: space.id, tab: nil)
            XCTFail("Without a username neither Apple nor Crest can keep the password.")
        } catch {
            XCTAssertEqual(error as? CredentialVaultError, .saveDecisionUnavailable)
        }
        XCTAssertTrue(incapable.saved.isEmpty)
        let anonymousDescriptors = try await anonymousVault.descriptors(in: space.id)
        XCTAssertTrue(anonymousDescriptors.isEmpty)
    }

    func testAPageDoesNotOfferAgainAGeneratedPasswordAppleAlreadyHolds() {
        let presaved = BrowserCredentialPresavedPassword(
            origin: origin, topLevelOrigin: origin, password: "generated", username: "ada")
        func submitted(username: String, password: String) -> BrowserCredentialSaveCandidate {
            BrowserCredentialSaveCandidate(
                id: UUID(), origin: origin, topLevelOrigin: origin, username: username, password: password,
                passwordKind: .new, isCrossOriginFrame: false, submittedAt: .now)
        }
        XCTAssertTrue(presaved.covers(submitted(username: "ada", password: "generated")))
        XCTAssertFalse(presaved.covers(submitted(username: "ada", password: "changed")))
        // A different account than the one Apple was sent is still offered.
        XCTAssertFalse(presaved.covers(submitted(username: "bob", password: "generated")))
        XCTAssertTrue(presaved.covers(submitted(username: "", password: "generated")))
        // Apple was sent no username, so a submission that adds one is still offered.
        let withoutUsername = BrowserCredentialPresavedPassword(
            origin: origin, topLevelOrigin: origin, password: "generated", username: "")
        XCTAssertFalse(withoutUsername.covers(submitted(username: "ada", password: "generated")))
        XCTAssertTrue(withoutUsername.covers(submitted(username: "", password: "generated")))
    }

    func testASiteAppleMarksNeverSaveOffersCrestOnlyAndSendsAppleNothing() async throws {
        var seed = SessionState.Seed.preview
        seed.spaces[0].settings.credentialPreferences = Self.preferences(usesApplePasswords: true)
        let space = seed.spaces[0]
        let crestVault = InMemoryCredentialVault()
        let store = BrowserStore(seed: seed, credentialVault: crestVault)
        let access = FakeAppleAccess(
            core: store.core, source: FakeAppleSource(logins: [], password: ""), neverSaveAnswer: .neverSaves)
        store.applePasswords = access
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(), origin: origin, topLevelOrigin: origin, username: "ada", password: "secret",
            passwordKind: .new, isCrossOriginFrame: false, submittedAt: .now)

        let model = BrowserCredentialSavePromptModel()
        await model.prepare(candidate: candidate, in: space.id, tab: nil, browser: store)
        XCTAssertEqual(model.destination, .crestPasswords)
        XCTAssertNil(model.alternateDestination)
        XCTAssertTrue(model.appleNeverSaves)

        // A generated password is kept in Crest at once, with nothing sent to Apple.
        let wasSent = try await store.keepGeneratedPassword(candidate, in: space.id, tab: nil)
        XCTAssertFalse(wasSent)
        XCTAssertTrue(access.saved.isEmpty)
        let kept = try await crestVault.descriptors(in: space.id)
        XCTAssertEqual(kept.map(\.username), ["ada"])
    }

    func testAFailedNeverSaveLookupKeepsAGeneratedPasswordInCrestAndSendsAppleNothing() async throws {
        var seed = SessionState.Seed.preview
        seed.spaces[0].settings.credentialPreferences = Self.preferences(usesApplePasswords: true)
        let space = seed.spaces[0]
        let crestVault = InMemoryCredentialVault()
        let store = BrowserStore(seed: seed, credentialVault: crestVault)
        let access = FakeAppleAccess(
            core: store.core, source: FakeAppleSource(logins: [], password: ""), neverSaveAnswer: .unknown)
        store.applePasswords = access
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(), origin: origin, topLevelOrigin: origin, username: "ada", password: "generated",
            passwordKind: .new, isCrossOriginFrame: false, submittedAt: .now)

        let wasSent = try await store.keepGeneratedPassword(candidate, in: space.id, tab: nil)
        XCTAssertFalse(wasSent)
        XCTAssertTrue(access.saved.isEmpty)
        let kept = try await crestVault.descriptors(in: space.id)
        XCTAssertEqual(kept.map(\.username), ["ada"])
    }

    func testAnUnpairedSpaceSavesToCrestExactlyAsBefore() async throws {
        var seed = SessionState.Seed.preview
        seed.spaces[0].settings.credentialPreferences = Self.preferences(usesApplePasswords: true)
        let space = seed.spaces[0]
        let store = BrowserStore(seed: seed, credentialVault: InMemoryCredentialVault())
        let access = FakeAppleAccess(
            core: store.core, source: FakeAppleSource(logins: [], password: ""), helper: .unpaired)
        store.applePasswords = access
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(), origin: origin, topLevelOrigin: origin, username: "ada", password: "secret",
            passwordKind: .new, isCrossOriginFrame: false, submittedAt: .now)

        let model = BrowserCredentialSavePromptModel()
        await model.prepare(candidate: candidate, in: space.id, tab: nil, browser: store)

        XCTAssertEqual(model.destination, .crestPasswords)
        XCTAssertNil(model.alternateDestination)
        XCTAssertEqual(model.phase, .create)
        XCTAssertTrue(access.saved.isEmpty)
    }

    private static func preferences(usesApplePasswords: Bool) -> CredentialPreferences {
        CredentialPreferences(
            isEnabled: true, syncsCrestPasswordsWithICloud: false, alsoOffersSaveToSystemPasswords: false,
            usesApplePasswords: usesApplePasswords)
    }
}

// MARK: - Fakes

@MainActor
private final class FakeAppleSource: ApplePasswordsCredentialSource {
    private let logins: [String]
    private let password: String
    private(set) var loginReads = 0
    private(set) var passwordReads = 0

    init(logins: [String], password: String) {
        self.logins = logins
        self.password = password
    }

    func logins(for origin: CredentialOrigin, tab: UUID?, support: ApplePasswordsSupport) async throws
        -> ApplePasswordsLoginNamesRequest.Logins
    {
        loginReads += 1
        return ApplePasswordsLoginNamesRequest.Logins(usernames: logins, neverSaves: false)
    }

    func password(for origin: CredentialOrigin, username: String, tab: UUID?, support: ApplePasswordsSupport)
        async throws -> String
    {
        passwordReads += 1
        return password
    }

    var canFillOneTimeCodes: Bool { false }

    func oneTimeCodes(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> [ApplePasswordsOneTimeCode] { [] }

    func currentOneTimeCode(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, domain: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> String { throw ApplePasswordsError.loginNotFound }
}

/// A paired helper in a Mac launch, whose availability the real core decides
/// from what the store passes in.
@MainActor
private final class FakeAppleAccess: BrowserApplePasswordsAccess {
    private let vault: ApplePasswordsCredentialVault
    private(set) var saved: [BrowserCredentialSaveCandidate] = []
    let savesAccountsWithoutUsername: Bool
    private let sendFails: Bool
    private let neverSaveAnswer: ApplePasswordsNeverSaveAnswer
    private let core: CrestCore
    private let helper: ApplePasswordsHelperFact

    init(
        core: CrestCore, source: FakeAppleSource, helper: ApplePasswordsHelperFact = .paired,
        savesAccountsWithoutUsername: Bool = true, sendFails: Bool = false,
        neverSaveAnswer: ApplePasswordsNeverSaveAnswer = .notNever
    ) {
        self.neverSaveAnswer = neverSaveAnswer
        self.savesAccountsWithoutUsername = savesAccountsWithoutUsername
        self.sendFails = sendFails
        self.core = core
        self.helper = helper
        vault = ApplePasswordsCredentialVault(source: source) { _ in
            ApplePasswordsSupport(status: .available, offersToTurnOffExtension: false)
        }
    }

    func support(
        for space: BrowserSpaceIdentity, preferences: CredentialPreferences, isPrivateBrowsing: Bool
    ) -> ApplePasswordsSupport? {
        try? core.query(
            ApplePasswordsAvailability(
                isMacPlatform: true, hasManagedBrowserCapability: true, isLaunchIsolated: false,
                isPrivateBrowsing: isPrivateBrowsing, spaceCredentialsEnabled: preferences.isEnabled,
                spaceUsesApplePasswords: preferences.usesApplePasswords, applePasswordsExtensionEnabled: false,
                helper: helper))
    }

    func couldStartHelper(
        for space: BrowserSpaceIdentity, preferences: CredentialPreferences, isPrivateBrowsing: Bool
    ) -> Bool { false }

    func start(support: ApplePasswordsSupport) async {}

    func descriptors(
        matching origin: CredentialOrigin, in spaceID: UUID, tab: UUID?
    ) async throws -> [CredentialDescriptor] {
        try await vault.descriptors(matching: origin, in: spaceID, tab: tab)
    }

    func credential(id: UUID, in spaceID: UUID, tab: UUID?) async throws -> BrowserCredential? {
        try await vault.credential(id: id, in: spaceID, tab: tab)
    }

    var canFillOneTimeCodes: Bool { false }
    var oneTimeCodeArrivals: Int { 0 }

    func oneTimeCodes(
        for origin: CredentialOrigin, topLevelOrigin: CredentialOrigin, in spaceID: UUID, username: String?,
        tab: UUID?, support: ApplePasswordsSupport
    ) async throws -> [BrowserOneTimeCodeSuggestion] { [] }

    func oneTimeCode(
        for suggestionID: UUID, origin: CredentialOrigin, topLevelOrigin: CredentialOrigin, in spaceID: UUID,
        tab: UUID?, support: ApplePasswordsSupport
    ) async throws -> String { throw ApplePasswordsError.notPermitted }

    func forgetOneTimeCodes(tab: UUID?) {}

    func neverSaves(
        for origin: CredentialOrigin, tab: UUID?, support: ApplePasswordsSupport
    ) async -> ApplePasswordsNeverSaveAnswer {
        neverSaveAnswer
    }

    func openPasswordsApp(for origin: CredentialOrigin, support: ApplePasswordsSupport) async throws {}

    func save(_ candidate: BrowserCredentialSaveCandidate, tab: UUID?, support: ApplePasswordsSupport) async throws {
        if sendFails { throw ApplePasswordsError.notPaired }
        saved.append(candidate)
    }

    func requestPairingCode(support: ApplePasswordsSupport) async -> BrowserApplePasswordsPairingOutcome { .failed }

    func completePairing(code: String, support: ApplePasswordsSupport) async -> BrowserApplePasswordsPairingOutcome {
        .failed
    }

    func cancelPairing() async {}

    func rowsWereShown(support: ApplePasswordsSupport, in space: BrowserSpaceIdentity) {}

    func turnOffExtension(in space: BrowserSpaceIdentity) {}
}

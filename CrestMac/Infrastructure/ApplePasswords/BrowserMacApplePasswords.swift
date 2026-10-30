import Foundation
import Observation

/// The Mac's Apple Passwords, as shared code reaches it. Every answer about
/// whether Apple Passwords may be used comes from the core's
/// `ApplePasswordsAvailability` query; this class supplies the launch's facts
/// and carries out what the core allows.
@Observable
@MainActor
final class BrowserMacApplePasswords: BrowserApplePasswordsAccess {
    // MARK: - Variables

    /// How often the helper announced that a one-time code arrived.
    private(set) var oneTimeCodeArrivals = 0
    /// Follows the windows' tabs and tells the helper about them.
    @ObservationIgnored let tabEvents: BrowserMacApplePasswordsTabEvents

    @ObservationIgnored private let vault: ApplePasswordsCredentialVault
    @ObservationIgnored private let oneTimeCodeRows: ApplePasswordsOneTimeCodes
    @ObservationIgnored private let core: CrestCore
    @ObservationIgnored private let helper: ApplePasswordsHelper
    @ObservationIgnored private let launchEnvironment: BrowserLaunchEnvironment
    /// The standard windows' store, whose Spaces the vault answers for.
    @ObservationIgnored private weak var browser: BrowserStore?
    @ObservationIgnored private var spacesToldAboutExtension: Set<UUID> = []
    @ObservationIgnored private var toldHelperIsUnavailable = false

    // MARK: - Initializers

    init(
        core: CrestCore, browser: BrowserStore, helper: ApplePasswordsHelper,
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) {
        self.core = core
        self.browser = browser
        self.helper = helper
        self.launchEnvironment = launchEnvironment
        let appleVault = ApplePasswordsCredentialVault(source: helper) {
            [weak browser, weak helper, weak core] spaceID in
            await Self.support(for: spaceID, browser: browser, helper: helper, core: core)
        }
        oneTimeCodeRows = ApplePasswordsOneTimeCodes(source: helper)
        vault = appleVault
        tabEvents = BrowserMacApplePasswordsTabEvents(helper: helper, launchEnvironment: launchEnvironment)
        helper.onProcessEnd = { Task { await appleVault.forgetIssued() } }
        helper.onStateChange = { [weak self] state in self?.helperStateChanged(state) }
        helper.onOneTimeCodeAvailable = { [weak self] in self?.oneTimeCodeArrivals += 1 }
    }

    // MARK: - Actions - Availability

    func support(
        for space: BrowserSpaceIdentity, preferences: CredentialPreferences, isPrivateBrowsing: Bool
    ) -> ApplePasswordsSupport? {
        answer(
            helper: helper.state, space: space, preferences: preferences, isPrivateBrowsing: isPrivateBrowsing)
    }

    func couldStartHelper(
        for space: BrowserSpaceIdentity, preferences: CredentialPreferences, isPrivateBrowsing: Bool
    ) -> Bool {
        var turnedOn = preferences
        turnedOn.usesApplePasswords = true
        return answer(helper: .stopped, space: space, preferences: turnedOn, isPrivateBrowsing: isPrivateBrowsing)?
            .status.startsHelper ?? false
    }

    private func answer(
        helper state: ApplePasswordsHelper.State, space: BrowserSpaceIdentity, preferences: CredentialPreferences,
        isPrivateBrowsing: Bool
    ) -> ApplePasswordsSupport? {
        try? core.query(
            BrowserApplePasswordsSystem.availability(
                helper: state, preferences: preferences, isPrivateBrowsing: isPrivateBrowsing,
                applePasswordsExtensionEnabled: Self.isAppleExtensionEnabled(in: space),
                launchEnvironment: launchEnvironment))
    }

    /// The vault asks again for every read, with the Space as it is now.
    private static func support(
        for spaceID: UUID, browser: BrowserStore?, helper: ApplePasswordsHelper?, core: CrestCore?
    ) -> ApplePasswordsSupport? {
        guard let browser, let helper, let core, let space = browser.spaceModel(spaceID) else { return nil }
        let query = BrowserApplePasswordsSystem.availability(
            helper: helper.state, preferences: space.settings.credentialPreferences,
            isPrivateBrowsing: browser.isPrivateBrowsing,
            applePasswordsExtensionEnabled: isAppleExtensionEnabled(in: space.identity))
        return try? core.query(query)
    }

    /// Only the Chromium engine knows its extensions, and only from what it has
    /// already read for the Space.
    private static func isAppleExtensionEnabled(in space: BrowserSpaceIdentity) -> Bool {
        #if CREST_CHROMIUM_HOST
            return ChromiumComposition.extensions.isApplePasswordsExtensionEnabled(in: space)
        #else
            return false
        #endif
    }

    // MARK: - Actions - Helper

    func start(support: ApplePasswordsSupport) async {
        await helper.start(support: support)
    }

    func requestPairingCode(support: ApplePasswordsSupport) async -> BrowserApplePasswordsPairingOutcome {
        do {
            try await helper.requestPairingCode(support: support)
            return .codeShown
        } catch {
            return (error as? ApplePasswordsPairingError)?.outcome ?? .failed
        }
    }

    func completePairing(code: String, support: ApplePasswordsSupport) async -> BrowserApplePasswordsPairingOutcome {
        do {
            try await helper.completePairing(code: code, support: support)
            return .paired
        } catch {
            return (error as? ApplePasswordsPairingError)?.outcome ?? .failed
        }
    }

    func cancelPairing() async {
        helper.cancelPairing()
    }

    // MARK: - Actions - Saving

    var savesAccountsWithoutUsername: Bool { helper.savesAccountsWithoutUsername }

    func save(_ candidate: BrowserCredentialSaveCandidate, tab: UUID?, support: ApplePasswordsSupport) async throws {
        try await helper.save(
            candidate.username, candidate.password, for: candidate.origin,
            form: .capturing(candidate.passwordKind), tab: tab, support: support)
    }

    // MARK: - Actions - Reading

    func descriptors(
        matching origin: CredentialOrigin, in spaceID: UUID, tab: UUID?
    ) async throws -> [CredentialDescriptor] {
        try await vault.descriptors(matching: origin, in: spaceID, tab: tab)
    }

    func credential(id: UUID, in spaceID: UUID, tab: UUID?) async throws -> BrowserCredential? {
        try await vault.credential(id: id, in: spaceID, tab: tab)
    }

    // MARK: - Actions - One-time codes

    var canFillOneTimeCodes: Bool { helper.canFillOneTimeCodes }

    func oneTimeCodes(
        for origin: CredentialOrigin, topLevelOrigin: CredentialOrigin, in spaceID: UUID, username: String?,
        tab: UUID?, support: ApplePasswordsSupport
    ) async throws -> [BrowserOneTimeCodeSuggestion] {
        try await oneTimeCodeRows.rows(
            for: origin, topLevelOrigin: topLevelOrigin, in: spaceID, username: username, tab: tab,
            support: support)
    }

    func oneTimeCode(
        for suggestionID: UUID, origin: CredentialOrigin, topLevelOrigin: CredentialOrigin, in spaceID: UUID,
        tab: UUID?, support: ApplePasswordsSupport
    ) async throws -> String {
        try await oneTimeCodeRows.code(
            for: suggestionID, origin: origin, topLevelOrigin: topLevelOrigin, in: spaceID, tab: tab, support: support)
    }

    func forgetOneTimeCodes(tab: UUID?) {
        oneTimeCodeRows.forget(tab: tab)
    }

    /// Asks Apple about the site with the same query that lists its logins, so
    /// the same timeouts bound it. Any failure reads as `unknown`.
    func neverSaves(
        for origin: CredentialOrigin, tab: UUID?, support: ApplePasswordsSupport
    ) async -> ApplePasswordsNeverSaveAnswer {
        guard let logins = try? await helper.logins(for: origin, tab: tab, support: support) else { return .unknown }
        return logins.neverSaves ? .neverSaves : .notNever
    }

    // MARK: - Actions - Passwords app

    func openPasswordsApp(for origin: CredentialOrigin, support: ApplePasswordsSupport) async throws {
        try await helper.openPasswordsApp(for: origin, support: support)
    }

    // MARK: - Actions - Notices

    func rowsWereShown(support: ApplePasswordsSupport, in space: BrowserSpaceIdentity) {
        guard support.offersToTurnOffExtension, spacesToldAboutExtension.insert(space.id).inserted else { return }
        BrowserNoticeCenter.shared.post(
            BrowserNotice(
                message: String(localized: "Apple’s iCloud Passwords extension is also on"),
                systemImage: "key.fill",
                action: BrowserNoticeAction(title: String(localized: "Turn Off")) { [weak self] in
                    self?.turnOffExtension(in: space)
                }))
    }

    func turnOffExtension(in space: BrowserSpaceIdentity) {
        #if CREST_CHROMIUM_HOST
            ChromiumComposition.extensions.command(
                .disable, extensionID: BrowserApplePasswordsSystem.appleExtensionID, space: space)
        #endif
    }

    /// Tells the person once per launch that the helper stopped being usable.
    private func helperStateChanged(_ state: ApplePasswordsHelper.State) {
        if state != .paired { oneTimeCodeRows.forgetAll() }
        guard case .unavailable = state, !toldHelperIsUnavailable else { return }
        toldHelperIsUnavailable = true
        BrowserNoticeCenter.shared.post(
            BrowserNotice(message: String(localized: "Apple Passwords isn’t available"), systemImage: "key.fill"))
    }
}

import Foundation

// MARK: - Suggestion Loading

extension BrowserStore: BrowserCredentialSuggestionLoading {
    /// Crest's own passwords for the site, then Apple Passwords' when the Space
    /// uses them and the core allows it. Apple Passwords never fails the list:
    /// a lookup that fails leaves Crest's rows and is logged.
    func credentialOffer(
        for origin: CredentialOrigin,
        in spaceID: UUID,
        tab: UUID?
    ) async throws -> BrowserCredentialOffer {
        guard let url = URL(string: origin.description) else {
            throw CredentialVaultError.invalidOrigin
        }
        let crest = try await credentialSuggestions(for: url, in: spaceID)
        var offer = BrowserCredentialOffer(
            suggestions: crest.map { BrowserCredentialSuggestion(descriptor: $0, provider: .crestPasswords) },
            offersApplePasswordsPairing: false)
        guard origin.isSecure, let access = applePasswords,
            let support = await startedApplePasswordsSupport(in: spaceID)
        else {
            return offer
        }
        offer.offersApplePasswordsPairing = support.status.needsPairing
        // Apple Passwords is on for the Space, paired or not, so its app can be opened on the site.
        offer.offersOpeningPasswordsApp = support.status.startsHelper
        guard support.status.offersApplePasswords, let space = spaceModel(spaceID) else { return offer }
        do {
            let apple = try await access.descriptors(matching: origin, in: spaceID, tab: tab)
            offer.suggestions += apple.map { BrowserCredentialSuggestion(descriptor: $0, provider: .applePasswords) }
            if !apple.isEmpty { access.rowsWereShown(support: support, in: space.identity) }
        } catch {
            DiagnosticLog.applePasswords.error("Apple Passwords suggestions failed: \(DiagnosticLog.describe(error))")
        }
        return offer
    }

    /// The one-time codes Apple Passwords holds for the frame that asked, and
    /// nothing else: a code field is offered no password rows. Where Apple
    /// Passwords cannot be used, or the helper does not fill codes, or the
    /// lookup fails, the offer is empty and the failure is logged.
    func oneTimeCodeOffer(
        for request: BrowserCredentialFillRequest,
        in spaceID: UUID,
        tab: UUID?
    ) async throws -> BrowserCredentialOffer {
        let none = BrowserCredentialOffer(suggestions: [], offersApplePasswordsPairing: false)
        guard request.origin.isSecure, let access = applePasswords,
            spaceModel(spaceID)?.settings.credentialPreferences.isEnabled == true,
            let support = await startedApplePasswordsSupport(in: spaceID),
            support.status.offersApplePasswords, access.canFillOneTimeCodes
        else {
            return none
        }
        do {
            let codes = try await access.oneTimeCodes(
                for: request.origin, topLevelOrigin: request.topLevelOrigin, in: spaceID,
                username: request.usernameHint, tab: tab, support: support)
            return BrowserCredentialOffer(suggestions: [], offersApplePasswordsPairing: false, codes: codes)
        } catch {
            DiagnosticLog.applePasswords.error("Apple Passwords codes failed: \(DiagnosticLog.describe(error))")
            return none
        }
    }

    /// The code a row stands for, to put into the field of `request` only. The
    /// core's answer for the Space is asked again; a row never fills a frame
    /// other than the one it was issued for.
    func oneTimeCode(
        for suggestion: BrowserOneTimeCodeSuggestion,
        request: BrowserCredentialFillRequest,
        in spaceID: UUID,
        tab: UUID?
    ) async throws -> String {
        guard request.origin.isSecure, let access = applePasswords,
            spaceModel(spaceID)?.settings.credentialPreferences.isEnabled == true,
            let support = applePasswordsSupport(in: spaceID), support.status.offersApplePasswords,
            access.canFillOneTimeCodes
        else {
            throw CredentialVaultError.credentialManagerDisabled
        }
        return try await access.oneTimeCode(
            for: suggestion.id, origin: request.origin, topLevelOrigin: request.topLevelOrigin, in: spaceID,
            tab: tab, support: support)
    }

    /// The prompt of a code field went away.
    func forgetOneTimeCodes(tab: UUID?) {
        applePasswords?.forgetOneTimeCodes(tab: tab)
    }

    /// How often the helper announced a code, for a prompt that looks again.
    var oneTimeCodeArrivals: Int { applePasswords?.oneTimeCodeArrivals ?? 0 }

    /// The core's answer for the Space, after starting the helper where the
    /// answer says to; the helper's state is part of the core's question.
    private func startedApplePasswordsSupport(in spaceID: UUID) async -> ApplePasswordsSupport? {
        guard let access = applePasswords, let support = applePasswordsSupport(in: spaceID) else { return nil }
        guard support.status.startsHelper else { return support }
        await access.start(support: support)
        return applePasswordsSupport(in: spaceID)
    }

    func openApplePasswordsApp(for origin: CredentialOrigin, in spaceID: UUID) async {
        guard origin.isSecure, let access = applePasswords, let support = applePasswordsSupport(in: spaceID) else {
            return
        }
        do {
            try await access.openPasswordsApp(for: origin, support: support)
        } catch {
            DiagnosticLog.applePasswords.error("Opening the Passwords app failed: \(DiagnosticLog.describe(error))")
        }
    }

    func requestApplePasswordsPairingCode(in spaceID: UUID) async -> BrowserApplePasswordsPairingOutcome {
        guard let access = applePasswords, let support = applePasswordsSupport(in: spaceID),
            support.status.needsPairing
        else { return .failed }
        return await access.requestPairingCode(support: support)
    }

    func completeApplePasswordsPairing(code: String, in spaceID: UUID) async -> BrowserApplePasswordsPairingOutcome {
        guard let access = applePasswords, let support = applePasswordsSupport(in: spaceID),
            support.status.needsPairing
        else { return .failed }
        return await access.completePairing(code: code, support: support)
    }

    func cancelApplePasswordsPairing() async {
        await applePasswords?.cancelPairing()
    }
}

// MARK: - Routing and availability

extension BrowserStore {
    /// The saved account a suggestion stands for, read from the vault that
    /// issued it. An identifier one vault issued is unknown to the other, so a
    /// row never fills through a vault that did not list it.
    func credential(
        for suggestion: BrowserCredentialSuggestion, in spaceID: UUID, tab: UUID?
    ) async throws -> BrowserCredential? {
        guard spaceModel(spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        if suggestion.provider.keepsSpaceVault {
            return try await credentialVault.credential(id: suggestion.id, in: spaceID)
        }
        return try await applePasswords?.credential(id: suggestion.id, in: spaceID, tab: tab)
    }

    /// The core's answer for the Space, or nil on a store without Apple
    /// Passwords or when the core cannot answer.
    func applePasswordsSupport(in spaceID: UUID) -> ApplePasswordsSupport? {
        guard let space = spaceModel(spaceID) else { return nil }
        return applePasswords?.support(
            for: space.identity, preferences: space.settings.credentialPreferences,
            isPrivateBrowsing: isPrivateBrowsing)
    }

    /// Whether the Space's settings offer Apple Passwords: this launch could
    /// start the helper for a Space that turned it on.
    func offersApplePasswordsSetting(in space: SpaceModel) -> Bool {
        applePasswords?.couldStartHelper(
            for: space.identity, preferences: space.settings.credentialPreferences,
            isPrivateBrowsing: isPrivateBrowsing) ?? false
    }
}

// MARK: - Saving

/// Whether a captured password may go to Apple Passwords, once Apple has been
/// asked about the site.
enum ApplePasswordsSaveAnswer {
    /// Apple Passwords is not on offer for this save.
    case unavailable
    /// Apple said the site is not never-save.
    case available(ApplePasswordsSupport)
    /// Apple could not be asked. The prompt may still offer Apple, since the
    /// person confirms there, but nothing is sent to it unasked.
    case unverified(ApplePasswordsSupport)
    /// Apple marks the site never-save, so only Crest's own vault is offered.
    case neverSaves

    /// The support to send with, only where Apple said the site is not never-save.
    var support: ApplePasswordsSupport? {
        guard case .available(let support) = self else { return nil }
        return support
    }

    /// The support to offer Apple with, where a person still confirms.
    var offerableSupport: ApplePasswordsSupport? {
        switch self {
        case .available(let support), .unverified(let support): support
        case .unavailable, .neverSaves: nil
        }
    }

    var neverSaves: Bool {
        if case .neverSaves = self { return true }
        return false
    }
}

extension BrowserStore {
    /// `applePasswordsSaveSupport(for:in:)`, then Apple's own never-save mark for
    /// the site. Nothing is offered to Apple on a site it marks never-save.
    func applePasswordsSaveAnswer(
        for candidate: BrowserCredentialSaveCandidate, in spaceID: UUID, tab: UUID?
    ) async -> ApplePasswordsSaveAnswer {
        guard let support = applePasswordsSaveSupport(for: candidate, in: spaceID), let access = applePasswords
        else { return .unavailable }
        return switch await access.neverSaves(for: candidate.origin, tab: tab, support: support) {
        case .neverSaves: .neverSaves
        case .notNever: .available(support)
        case .unknown: .unverified(support)
        }
    }

    /// The core's answer for the Space when a captured password can be offered
    /// to Apple Passwords: the Space uses it, the core offers it (paired and
    /// available, never in a private window or an isolated launch), and the
    /// candidate's origin is https, and the helper can save the account (one
    /// without a username needs a helper that says it can). Nil means the save
    /// goes to Crest as usual.
    func applePasswordsSaveSupport(
        for candidate: BrowserCredentialSaveCandidate, in spaceID: UUID
    ) -> ApplePasswordsSupport? {
        guard candidate.origin.isSecure, !isPrivateBrowsing, let access = applePasswords,
            !candidate.username.isEmpty || access.savesAccountsWithoutUsername,
            spaceModel(spaceID)?.settings.credentialPreferences.usesApplePasswords == true,
            let support = applePasswordsSupport(in: spaceID), support.status.offersApplePasswords
        else { return nil }
        return support
    }

    /// Keeps a generated password before it is filled, so it is never lost.
    /// Where the Space's destination is Apple Passwords it is sent there; any
    /// failure, or an account without a username that the helper cannot save,
    /// keeps it in Crest's vault instead.
    /// - Returns: Whether it was sent to Apple Passwords rather than kept in Crest.
    func keepGeneratedPassword(
        _ candidate: BrowserCredentialSaveCandidate, in spaceID: UUID, tab: UUID?
    ) async throws -> Bool {
        if await applePasswordsSaveAnswer(for: candidate, in: spaceID, tab: tab).support != nil {
            do {
                try await commitApplePasswordsSave(candidate, in: spaceID, tab: tab)
                return true
            } catch {
                DiagnosticLog.applePasswords.error(
                    "Sending a generated password failed: \(DiagnosticLog.describe(error))")
            }
        }
        _ = try await commitCredentialSave(candidate, in: spaceID)
        return false
    }

    /// Sends the candidate to Apple Passwords for the frame origin it was
    /// captured for, and writes nothing to Crest's vault. Apple decides whether
    /// the account is new or changed, so Crest's own match is not consulted.
    func commitApplePasswordsSave(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        tab: UUID?,
        now: Date = .now
    ) async throws {
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        guard let access = applePasswords,
            let support = await applePasswordsSaveAnswer(for: candidate, in: spaceID, tab: tab).support
        else {
            throw CredentialVaultError.credentialManagerDisabled
        }
        try await access.save(candidate, tab: tab, support: support)
    }
}

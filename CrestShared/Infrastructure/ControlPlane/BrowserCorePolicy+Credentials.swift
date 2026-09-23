import Foundation

/// Credential and passkey decisions answered by the portable core.
///
/// Only identities and metadata cross this boundary: origins, dates, record
/// identities, usernames where accounts are matched, and whether a field or a
/// value is present. Passwords never do. The stored-secret comparison a save
/// plan needs happens here, natively, and the core receives only its answer.
/// Every call has a fail-safe outcome: without an answer nothing is captured,
/// offered, saved or filled.
extension BrowserCorePolicy {
    // MARK: - Types

    enum CredentialCaptureAction: String, Decodable {
        case ignore, rememberUsername, dismissFill, offerFill, captureCandidate, offerSave, keepPending, discardPending
    }

    enum CredentialUsernameSource: String, Decodable {
        case none, explicit, hint
    }

    struct CredentialCaptureDecision: Equatable {
        let action: CredentialCaptureAction
        let usernameSource: CredentialUsernameSource
        let clearsUsernameHint: Bool
        let isCrossOriginFrame: Bool
        let anchorsToField: Bool
        let candidateLifetime: TimeInterval
        let usernameHintLifetime: TimeInterval
    }

    enum CredentialCaptureEvent: String, Encodable {
        case username, focus, submit, documentState, filled
    }

    enum CredentialSaveValidity: String, Decodable {
        case accepted, insecureOrigin, stale
    }

    enum CredentialSavePlanKind: String, Decodable {
        case create, update, alreadyStored
    }

    /// Where a fill's secret comes from, in the core's spelling.
    private enum CredentialFillSource: String, Encodable {
        case generated
        case saved
    }

    private struct CaptureRequest: Encodable {
        struct UsernameHint: Encodable {
            let origin: CredentialOrigin
            let topLevelOrigin: CredentialOrigin
            let capturedAt: TimeInterval
        }

        struct PendingCandidate: Encodable {
            let origin: CredentialOrigin
            let submittedAt: TimeInterval
        }

        let event: CredentialCaptureEvent
        let frameOrigin: CredentialOrigin
        let topLevelOrigin: CredentialOrigin
        let isMainFrame: Bool
        let hasFormID: Bool
        let hasUsername: Bool
        let hasPassword: Bool
        @BrowserCoreNullable var passwordKind: BrowserCredentialPasswordKind?
        @BrowserCoreNullable var hasVisiblePasswordField: Bool?
        let hasFillTarget: Bool
        let now: TimeInterval
        @BrowserCoreNullable var usernameHint: UsernameHint?
        @BrowserCoreNullable var pendingCandidate: PendingCandidate?
    }

    private struct CaptureAnswer: Decodable {
        let action: CredentialCaptureAction
        let usernameSource: CredentialUsernameSource
        let clearsUsernameHint: Bool
        let isCrossOriginFrame: Bool
        let anchorsToField: Bool
        let candidateLifetime: TimeInterval
        let usernameHintLifetime: TimeInterval
    }

    private struct FillRequest: Encodable {
        let passwordKind: BrowserCredentialPasswordKind
        let source: CredentialFillSource
    }

    private struct AllowedCredentialAnswer: Decodable {
        @BrowserCoreOptional var allowed: Bool?
    }

    private struct SaveValidityRequest: Encodable {
        let origin: CredentialOrigin
        let topLevelOrigin: CredentialOrigin
        let submittedAt: TimeInterval
        let now: TimeInterval
    }

    private struct SaveValidityAnswer: Decodable {
        @BrowserCoreOptional var verdict: CredentialSaveValidity?
    }

    /// One stored credential's identity and dates; a username only where an
    /// account is matched.
    private struct CredentialRecord: Encodable {
        let id: String
        let updatedAt: TimeInterval
        @BrowserCoreNullable var lastUsedAt: TimeInterval?
        var username: String?

        init(_ descriptor: CredentialDescriptor, includesUsername: Bool) {
            id = BrowserCorePolicy.coreID(descriptor.id)
            updatedAt = descriptor.updatedAt.timeIntervalSince1970
            lastUsedAt = descriptor.lastUsedAt?.timeIntervalSince1970
            username = includesUsername ? descriptor.username : nil
        }
    }

    private struct CredentialBatchRequest: Encodable {
        var username: String?
        let records: [CredentialRecord]
    }

    private struct CredentialWinnerAnswer: Decodable {
        @BrowserCoreOptional var id: String?
    }

    private struct SavePlanRequest: Encodable {
        struct Stored: Encodable {
            let id: String
            let passwordMatches: Bool
        }

        @BrowserCoreNullable var matchID: String?
        @BrowserCoreNullable var stored: Stored?
    }

    private struct SavePlanAnswer: Decodable {
        let plan: CredentialSavePlanKind
        @BrowserCoreOptional var id: String?
    }

    private struct PasswordRecipeRequest: Encodable {
        @BrowserCoreNullable var length: Int?
    }

    private struct PasswordRecipeAnswer: Decodable {
        let length: Int
        let groups: [String]
    }

    private struct PasskeyAccessRequest: Encodable {
        let hasManagedCapability: Bool
        let deviceConfiguration: BrowserPasskeyDeviceConfiguration
        let authorizationState: BrowserPasskeyAuthorizationState
    }

    private struct PasskeyAccessAnswer: Decodable {
        @BrowserCoreOptional var status: BrowserPasskeyAccessStatus?
    }

    private struct WriteThroughRequest: Encodable {
        let isMobilePlatform: Bool
        let supportsSystemAPI: Bool
        let hasManagedBrowserCapability: Bool
        let isLaunchIsolated: Bool
    }

    private struct WriteThroughAnswer: Decodable {
        @BrowserCoreOptional var availability: BrowserSystemPasswordWriteThroughAvailability?
    }

    private struct WriteThroughOfferRequest: Encodable {
        let offersSaveToSystemPasswords: Bool
        let availability: BrowserSystemPasswordWriteThroughAvailability
        let isPrivateBrowsing: Bool
    }

    private struct WriteThroughOfferAnswer: Decodable {
        @BrowserCoreOptional var offers: Bool?
    }

    // MARK: - Actions - Capture and fill

    /// What one form observation does to the page's credential state. Nil
    /// when the core cannot answer; the caller then captures and offers nothing.
    static func credentialCapture(
        _ event: CredentialCaptureEvent,
        frameOrigin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        isMainFrame: Bool,
        hasFormID: Bool,
        hasUsername: Bool,
        hasPassword: Bool,
        passwordKind: BrowserCredentialPasswordKind?,
        hasVisiblePasswordField: Bool?,
        hasFillTarget: Bool,
        usernameHint: BrowserCredentialUsernameHint?,
        pendingCandidate: BrowserCredentialSaveCandidate?,
        now: Date
    ) -> CredentialCaptureDecision? {
        let request = CaptureRequest(
            event: event, frameOrigin: frameOrigin, topLevelOrigin: topLevelOrigin, isMainFrame: isMainFrame,
            hasFormID: hasFormID, hasUsername: hasUsername, hasPassword: hasPassword, passwordKind: passwordKind,
            hasVisiblePasswordField: hasVisiblePasswordField, hasFillTarget: hasFillTarget,
            now: now.timeIntervalSince1970,
            usernameHint: usernameHint.map { hint in
                CaptureRequest.UsernameHint(
                    origin: hint.origin, topLevelOrigin: hint.topLevelOrigin,
                    capturedAt: hint.capturedAt.timeIntervalSince1970)
            },
            pendingCandidate: pendingCandidate.map { candidate in
                CaptureRequest.PendingCandidate(
                    origin: candidate.origin, submittedAt: candidate.submittedAt.timeIntervalSince1970)
            })
        guard let answer = evaluate(.credentialsCapture, request, answer: CaptureAnswer.self),
            answer.candidateLifetime > 0, answer.usernameHintLifetime > 0
        else { return nil }
        return CredentialCaptureDecision(
            action: answer.action, usernameSource: answer.usernameSource,
            clearsUsernameHint: answer.clearsUsernameHint, isCrossOriginFrame: answer.isCrossOriginFrame,
            anchorsToField: answer.anchorsToField, candidateLifetime: answer.candidateLifetime,
            usernameHintLifetime: answer.usernameHintLifetime)
    }

    /// Whether a fill request for this field may take a saved credential or a
    /// generated password. An unavailable core fills nothing.
    static func credentialFillAllowed(
        passwordKind: BrowserCredentialPasswordKind,
        generated: Bool
    ) -> Bool {
        let request = FillRequest(passwordKind: passwordKind, source: generated ? .generated : .saved)
        return evaluate(.credentialsFill, request, answer: AllowedCredentialAnswer.self)?.allowed ?? false
    }

    // MARK: - Actions - Saving

    /// Whether a save candidate may still be planned or committed. Nil when
    /// the core cannot answer.
    static func credentialSaveValidity(
        for candidate: BrowserCredentialSaveCandidate,
        now: Date
    ) -> CredentialSaveValidity? {
        let request = SaveValidityRequest(
            origin: candidate.origin, topLevelOrigin: candidate.topLevelOrigin,
            submittedAt: candidate.submittedAt.timeIntervalSince1970, now: now.timeIntervalSince1970)
        return evaluate(.credentialsSaveValidity, request, answer: SaveValidityAnswer.self)?.verdict
    }

    /// The most recent descriptor, or nil for an empty list. Throws when the
    /// core cannot answer.
    static func mostRecentCredential(
        _ descriptors: [CredentialDescriptor]
    ) throws -> CredentialDescriptor? {
        try reduceCredentials(descriptors, batchSize: 64, operation: .credentialsMostRecent) { batch in
            CredentialBatchRequest(records: batch.map { CredentialRecord($0, includesUsername: false) })
        }
    }

    /// The most recent descriptor for the same account as `username`, or nil.
    /// Throws when the core cannot answer.
    static func credentialSaveMatch(
        username: String,
        in descriptors: [CredentialDescriptor]
    ) throws -> CredentialDescriptor? {
        // Usernames make these records larger; smaller batches stay inside the
        // policy input limit.
        try reduceCredentials(descriptors, batchSize: 8, operation: .credentialsSaveMatch) { batch in
            CredentialBatchRequest(
                username: username, records: batch.map { CredentialRecord($0, includesUsername: true) })
        }
    }

    /// The save plan for a matched record and the native comparison of the
    /// candidate against its stored secret. Throws when the core cannot answer.
    static func credentialSavePlan(
        match: CredentialID?,
        storedPasswordMatches: Bool?
    ) throws -> CredentialSavePlanKind {
        let stored = match.flatMap { id in
            storedPasswordMatches.map { SavePlanRequest.Stored(id: coreID(id), passwordMatches: $0) }
        }
        let request = SavePlanRequest(matchID: match.map(coreID), stored: stored)
        guard let answer = evaluate(.credentialsSavePlan, request, answer: SavePlanAnswer.self),
            answer.plan == .create || answer.id == match.map(coreID)
        else { throw CredentialVaultError.saveDecisionUnavailable }
        return answer.plan
    }

    /// The composition of a generated password. The password itself is drawn
    /// natively, so it never enters the core.
    static func strongPasswordRecipe(length: Int?) -> (length: Int, groups: [[Character]])? {
        guard
            let answer = evaluate(
                .credentialsPasswordRecipe, PasswordRecipeRequest(length: length), answer: PasswordRecipeAnswer.self)
        else { return nil }
        let groups = answer.groups.map(Array.init)
        guard !groups.isEmpty, groups.allSatisfy({ !$0.isEmpty }), answer.length >= groups.count else { return nil }
        return (answer.length, groups)
    }

    // MARK: - Actions - Passkeys and system passwords

    /// Passkey access for websites. An unavailable core keeps checking, which
    /// never requests system consent.
    static func passkeyAccessStatus(
        hasManagedCapability: Bool,
        deviceConfiguration: BrowserPasskeyDeviceConfiguration,
        authorizationState: BrowserPasskeyAuthorizationState
    ) -> BrowserPasskeyAccessStatus {
        let request = PasskeyAccessRequest(
            hasManagedCapability: hasManagedCapability, deviceConfiguration: deviceConfiguration,
            authorizationState: authorizationState)
        return evaluate(.passkeysAccessStatus, request, answer: PasskeyAccessAnswer.self)?.status ?? .checking
    }

    /// Whether this build can offer saved passwords to the system's Passwords
    /// app. An unavailable core reports it unsupported.
    static func systemPasswordWriteThroughAvailability(
        isMobilePlatform: Bool,
        supportsSystemAPI: Bool,
        hasManagedBrowserCapability: Bool,
        isLaunchIsolated: Bool
    ) -> BrowserSystemPasswordWriteThroughAvailability {
        let request = WriteThroughRequest(
            isMobilePlatform: isMobilePlatform, supportsSystemAPI: supportsSystemAPI,
            hasManagedBrowserCapability: hasManagedBrowserCapability, isLaunchIsolated: isLaunchIsolated)
        return evaluate(.credentialsSystemWriteThrough, request, answer: WriteThroughAnswer.self)?.availability
            ?? .unsupportedPlatform
    }

    /// Whether a save prompt goes on to offer the password to the system's
    /// Passwords app. An unavailable core does not offer it.
    static func offersSystemPasswordWriteThrough(
        preferences: BrowserCredentialPreferences,
        availability: BrowserSystemPasswordWriteThroughAvailability,
        isPrivateBrowsing: Bool
    ) -> Bool {
        let request = WriteThroughOfferRequest(
            offersSaveToSystemPasswords: preferences.alsoOffersSaveToSystemPasswords, availability: availability,
            isPrivateBrowsing: isPrivateBrowsing)
        return evaluate(.credentialsSystemWriteThroughOffer, request, answer: WriteThroughOfferAnswer.self)?.offers
            ?? false
    }

    // MARK: - Actions - Batching

    /// Reduces a list in core-sized batches. The core's winner of winners is
    /// its winner of the whole list, so batching does not change the answer.
    private static func reduceCredentials(
        _ descriptors: [CredentialDescriptor],
        batchSize: Int,
        operation: BrowserPolicyOperation,
        request: ([CredentialDescriptor]) -> CredentialBatchRequest
    ) throws -> CredentialDescriptor? {
        func winner(of batch: [CredentialDescriptor]) throws -> CredentialDescriptor? {
            guard let answer = evaluate(operation, request(batch), answer: CredentialWinnerAnswer.self) else {
                throw CredentialVaultError.saveDecisionUnavailable
            }
            guard let id = answer.id else { return nil }
            guard let descriptor = batch.first(where: { coreID($0.id) == id }) else {
                throw CredentialVaultError.saveDecisionUnavailable
            }
            return descriptor
        }
        var remaining = descriptors
        while remaining.count > batchSize {
            remaining = try stride(from: 0, to: remaining.count, by: batchSize).compactMap { start in
                try winner(of: Array(remaining[start..<min(start + batchSize, remaining.count)]))
            }
        }
        return try winner(of: remaining)
    }

    private static func coreID(_ id: CredentialID) -> String {
        id.rawValue.coreIdentifier
    }
}

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
    enum CredentialCaptureAction: String {
        case ignore, rememberUsername, dismissFill, offerFill, captureCandidate, offerSave, keepPending, discardPending
    }

    enum CredentialUsernameSource: String {
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

    enum CredentialCaptureEvent: String {
        case username, focus, submit, documentState, filled
    }

    enum CredentialSaveValidity: String {
        case accepted, insecureOrigin, stale
    }

    enum CredentialSavePlanKind: String {
        case create, update, alreadyStored
    }

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
        guard let response = evaluate([
            "version": 1, "operation": "credentials.capture", "event": event.rawValue,
            "frameOrigin": coreOrigin(frameOrigin), "topLevelOrigin": coreOrigin(topLevelOrigin),
            "isMainFrame": isMainFrame, "hasFormID": hasFormID, "hasUsername": hasUsername,
            "hasPassword": hasPassword, "passwordKind": passwordKind?.rawValue as Any? ?? NSNull(),
            "hasVisiblePasswordField": hasVisiblePasswordField as Any? ?? NSNull(),
            "hasFillTarget": hasFillTarget, "now": now.timeIntervalSince1970,
            "usernameHint": usernameHint.map { hint in
                ["origin": coreOrigin(hint.origin), "topLevelOrigin": coreOrigin(hint.topLevelOrigin),
                 "capturedAt": hint.capturedAt.timeIntervalSince1970] as [String: Any]
            } as Any? ?? NSNull(),
            "pendingCandidate": pendingCandidate.map { candidate in
                ["origin": coreOrigin(candidate.origin),
                 "submittedAt": candidate.submittedAt.timeIntervalSince1970] as [String: Any]
            } as Any? ?? NSNull()
        ]),
            let action = (response["action"] as? String).flatMap(CredentialCaptureAction.init(rawValue:)),
            let source = (response["usernameSource"] as? String).flatMap(CredentialUsernameSource.init(rawValue:)),
            let clearsHint = response["clearsUsernameHint"] as? Bool,
            let crossOrigin = response["isCrossOriginFrame"] as? Bool,
            let anchors = response["anchorsToField"] as? Bool,
            let candidateLifetime = (response["candidateLifetime"] as? NSNumber)?.doubleValue,
            let hintLifetime = (response["usernameHintLifetime"] as? NSNumber)?.doubleValue,
            candidateLifetime > 0, hintLifetime > 0
        else { return nil }
        return CredentialCaptureDecision(
            action: action, usernameSource: source, clearsUsernameHint: clearsHint,
            isCrossOriginFrame: crossOrigin, anchorsToField: anchors,
            candidateLifetime: candidateLifetime, usernameHintLifetime: hintLifetime)
    }

    /// Whether a fill request for this field may take a saved credential or a
    /// generated password. An unavailable core fills nothing.
    static func credentialFillAllowed(
        passwordKind: BrowserCredentialPasswordKind,
        generated: Bool
    ) -> Bool {
        evaluate([
            "version": 1, "operation": "credentials.fill", "passwordKind": passwordKind.rawValue,
            "source": generated ? "generated" : "saved"
        ])?["allowed"] as? Bool ?? false
    }

    /// Whether a save candidate may still be planned or committed. Nil when
    /// the core cannot answer.
    static func credentialSaveValidity(
        for candidate: BrowserCredentialSaveCandidate,
        now: Date
    ) -> CredentialSaveValidity? {
        (evaluate([
            "version": 1, "operation": "credentials.save_validity",
            "origin": coreOrigin(candidate.origin), "topLevelOrigin": coreOrigin(candidate.topLevelOrigin),
            "submittedAt": candidate.submittedAt.timeIntervalSince1970, "now": now.timeIntervalSince1970
        ])?["verdict"] as? String).flatMap(CredentialSaveValidity.init(rawValue:))
    }

    /// The most recent descriptor, or nil for an empty list. Throws when the
    /// core cannot answer.
    static func mostRecentCredential(
        _ descriptors: [CredentialDescriptor]
    ) throws -> CredentialDescriptor? {
        try reduceCredentials(descriptors, batchSize: 64) { batch in
            ["version": 1, "operation": "credentials.most_recent",
             "records": batch.map { coreRecord($0, includesUsername: false) }]
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
        try reduceCredentials(descriptors, batchSize: 8) { batch in
            ["version": 1, "operation": "credentials.save_match", "username": username,
             "records": batch.map { coreRecord($0, includesUsername: true) }]
        }
    }

    /// The save plan for a matched record and the native comparison of the
    /// candidate against its stored secret. Throws when the core cannot answer.
    static func credentialSavePlan(
        match: CredentialID?,
        storedPasswordMatches: Bool?
    ) throws -> CredentialSavePlanKind {
        let stored: Any = match.flatMap { id in
            storedPasswordMatches.map { ["id": coreID(id), "passwordMatches": $0] as [String: Any] }
        } ?? NSNull()
        guard let response = evaluate([
            "version": 1, "operation": "credentials.save_plan",
            "matchID": match.map(coreID) as Any? ?? NSNull(), "stored": stored
        ]), let plan = (response["plan"] as? String).flatMap(CredentialSavePlanKind.init(rawValue:)),
            plan == .create || (response["id"] as? String) == match.map(coreID)
        else { throw CredentialVaultError.saveDecisionUnavailable }
        return plan
    }

    /// The composition of a generated password. The password itself is drawn
    /// natively, so it never enters the core.
    static func strongPasswordRecipe(length: Int?) -> (length: Int, groups: [[Character]])? {
        guard let response = evaluate([
            "version": 1, "operation": "credentials.password_recipe",
            "length": length as Any? ?? NSNull()
        ]), let resolved = response["length"] as? Int,
            let groups = (response["groups"] as? [String])?.map(Array.init),
            !groups.isEmpty, groups.allSatisfy({ !$0.isEmpty }), resolved >= groups.count
        else { return nil }
        return (resolved, groups)
    }

    /// Passkey access for websites. An unavailable core keeps checking, which
    /// never requests system consent.
    static func passkeyAccessStatus(
        hasManagedCapability: Bool,
        deviceConfiguration: BrowserPasskeyDeviceConfiguration,
        authorizationState: BrowserPasskeyAuthorizationState
    ) -> BrowserPasskeyAccessStatus {
        (evaluate([
            "version": 1, "operation": "passkeys.access_status",
            "hasManagedCapability": hasManagedCapability,
            "deviceConfiguration": deviceConfiguration.rawValue,
            "authorizationState": authorizationState.rawValue
        ])?["status"] as? String).flatMap(BrowserPasskeyAccessStatus.init(rawValue:)) ?? .checking
    }

    /// Whether this build can offer saved passwords to the system's Passwords
    /// app. An unavailable core reports it unsupported.
    static func systemPasswordWriteThroughAvailability(
        isMobilePlatform: Bool,
        supportsSystemAPI: Bool,
        hasManagedBrowserCapability: Bool,
        isLaunchIsolated: Bool
    ) -> BrowserSystemPasswordWriteThroughAvailability {
        (evaluate([
            "version": 1, "operation": "credentials.system_write_through",
            "isMobilePlatform": isMobilePlatform, "supportsSystemAPI": supportsSystemAPI,
            "hasManagedBrowserCapability": hasManagedBrowserCapability, "isLaunchIsolated": isLaunchIsolated
        ])?["availability"] as? String).flatMap(BrowserSystemPasswordWriteThroughAvailability.init(rawValue:))
            ?? .unsupportedPlatform
    }

    /// Whether a save prompt goes on to offer the password to the system's
    /// Passwords app. An unavailable core does not offer it.
    static func offersSystemPasswordWriteThrough(
        preferences: BrowserCredentialPreferences,
        availability: BrowserSystemPasswordWriteThroughAvailability,
        isPrivateBrowsing: Bool
    ) -> Bool {
        evaluate([
            "version": 1, "operation": "credentials.system_write_through_offer",
            "offersSaveToSystemPasswords": preferences.alsoOffersSaveToSystemPasswords,
            "availability": availability.rawValue, "isPrivateBrowsing": isPrivateBrowsing
        ])?["offers"] as? Bool ?? false
    }

    /// Reduces a list in core-sized batches. The core's winner of winners is
    /// its winner of the whole list, so batching does not change the answer.
    private static func reduceCredentials(
        _ descriptors: [CredentialDescriptor],
        batchSize: Int,
        request: ([CredentialDescriptor]) -> [String: Any]
    ) throws -> CredentialDescriptor? {
        func winner(of batch: [CredentialDescriptor]) throws -> CredentialDescriptor? {
            guard let response = evaluate(request(batch)) else {
                throw CredentialVaultError.saveDecisionUnavailable
            }
            guard let id = response["id"] as? String else { return nil }
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

    private static func coreOrigin(_ origin: CredentialOrigin) -> [String: Any] {
        ["scheme": origin.scheme, "host": origin.host, "port": origin.port]
    }

    private static func coreID(_ id: CredentialID) -> String {
        id.rawValue.uuidString.lowercased()
    }

    private static func coreRecord(_ descriptor: CredentialDescriptor, includesUsername: Bool) -> [String: Any] {
        var record: [String: Any] = [
            "id": coreID(descriptor.id), "updatedAt": descriptor.updatedAt.timeIntervalSince1970,
            "lastUsedAt": descriptor.lastUsedAt?.timeIntervalSince1970 as Any? ?? NSNull()
        ]
        if includesUsername { record["username"] = descriptor.username }
        return record
    }
}

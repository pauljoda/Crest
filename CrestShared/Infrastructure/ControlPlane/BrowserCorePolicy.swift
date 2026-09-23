import CrestCoreABI
import Foundation
import os

/// A stateless boundary for synchronous domain decisions. Session mutations
/// remain commands to the core session authority.
enum BrowserCorePolicy {
    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "CorePolicy")

    /// The link decision when the core cannot answer. A person's own top-level
    /// click opens a new tab in the same Space, so a pinned or saved tab never
    /// leaves the page it keeps and nothing opens as a Peek or crosses a
    /// profile; a script or subframe navigation keeps the engine's own
    /// in-place behavior, which Crest never intercepts.
    private static func unansweredLinkNavigation(isUserActivatedLink: Bool, isTopLevelNavigation: Bool)
        -> BrowserLinkNavigationDecision {
        isUserActivatedLink && isTopLevelNavigation ? .foregroundTab : .navigate
    }

    static func modifiedLinkNavigation(destinationURL: URL?, context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool, isTopLevelNavigation: Bool, isCommandModified: Bool,
        isOptionModified: Bool, isMiddleClick: Bool, peekModifier: BrowserLinkClickModifier,
        isShiftModified: Bool, focusesNewTabs: Bool) -> BrowserLinkNavigationDecision {
        guard let response = evaluate([
            "version": 1, "operation": "navigation.modified_link",
            "url": destinationURL?.absoluteString as Any? ?? NSNull(),
            "userActivatedLink": isUserActivatedLink, "topLevel": isTopLevelNavigation,
            "commandModified": isCommandModified, "optionModified": isOptionModified,
            "middleClick": isMiddleClick, "peekModifier": peekModifier.rawValue,
            "shiftModified": isShiftModified, "focusesNewTabs": focusesNewTabs,
            "hasContext": context != nil, "placement": context?.placement.rawValue as Any? ?? NSNull(),
            "savedUrl": context?.savedURL?.absoluteString as Any? ?? NSNull(),
            "automaticallyOpensPeek": context?.automaticallyOpensPeek ?? false
        ]), let value = response["decision"] as? String,
            let decision = BrowserLinkNavigationDecision(rawValue: value)
        else {
            return unansweredLinkNavigation(isUserActivatedLink: isUserActivatedLink,
                isTopLevelNavigation: isTopLevelNavigation)
        }
        return decision
    }
    static func linkNavigation(destinationURL: URL?, context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool, isTopLevelNavigation: Bool, isPeekModified: Bool,
        isNewTabModified: Bool, isShiftModified: Bool, focusesNewTabs: Bool) -> BrowserLinkNavigationDecision {
        guard let response = evaluate([
            "version": 1, "operation": "navigation.link",
            "url": destinationURL?.absoluteString as Any? ?? NSNull(),
            "userActivatedLink": isUserActivatedLink, "topLevel": isTopLevelNavigation,
            "peekModified": isPeekModified, "newTabModified": isNewTabModified,
            "shiftModified": isShiftModified, "focusesNewTabs": focusesNewTabs,
            "hasContext": context != nil, "placement": context?.placement.rawValue as Any? ?? NSNull(),
            "savedUrl": context?.savedURL?.absoluteString as Any? ?? NSNull(),
            "automaticallyOpensPeek": context?.automaticallyOpensPeek ?? false
        ]), let value = response["decision"] as? String,
            let decision = BrowserLinkNavigationDecision(rawValue: value)
        else {
            return unansweredLinkNavigation(isUserActivatedLink: isUserActivatedLink,
                isTopLevelNavigation: isTopLevelNavigation)
        }
        return decision
    }
    static func addressIntent(_ input: String, provider: BrowserSearchProvider) -> BrowserAddressIntent? {
        let allowsInternalPages = BrowserEngineRegistration.current.supports(.internalPages)
        guard let response = evaluate([
            "version": 1, "operation": "address.intent", "input": input,
            "allowsInternalPages": allowsInternalPages,
            "searchProvider": provider.coreDescriptor
        ]), let text = response["url"] as? String, let url = URL(string: text) else { return nil }
        if let query = response["searchQuery"] as? String { return .search(query: query, provider: provider, url: url) }
        return .open(url)
    }
    static func normalizedHistoryURL(_ url: URL) -> URL? {
        guard let text = evaluate(["version": 1, "operation": "history.normalize", "url": url.absoluteString])?["url"] as? String
        else { return nil }
        return URL(string: text)
    }
    /// One off-screen page as the native store sees it. `inactiveSince` is
    /// missing for an engine tab that holds no Crest page of its own.
    struct ResidencyCandidate {
        let tabID: TabID
        var inactiveSince: Date?
        var keepsPageLoaded = false
        var presentedIndex: Int?

        init(tabID: TabID, inactiveSince: Date?, keepsPageLoaded: Bool = false, presentedIndex: Int? = nil) {
            self.tabID = tabID
            self.inactiveSince = inactiveSince
            self.keepsPageLoaded = keepsPageLoaded
            self.presentedIndex = presentedIndex
        }
    }
    /// How many eligible pages this squeeze may take back. A core that cannot
    /// answer releases nothing rather than guessing at a budget.
    static func memoryPressureReleaseLimit(level: BrowserMemoryPressureLevel, eligiblePageCount: Int,
        platform: BrowserMemoryPressurePlatform) -> Int {
        guard let limit = evaluate(["version": 1, "operation": "residency.release_limit",
            "level": level.rawValue, "platform": platform.rawValue,
            "eligiblePageCount": eligiblePageCount])?["limit"] as? Int, limit >= 0 else { return 0 }
        return limit
    }
    /// The order in which release should be attempted. The caller still asks
    /// each page's engine for the residency veto and re-validates ownership
    /// after every await; `presentedFallback` is only used when the off-screen
    /// sweep released nobody at all.
    static func residencyReleasePlan(level: BrowserMemoryPressureLevel, platform: BrowserMemoryPressurePlatform,
        candidates: [ResidencyCandidate], focusedIndex: Int?)
        -> (offScreen: [TabID], presentedFallback: [TabID]) {
        guard let response = evaluate([
            "version": 1, "operation": "residency.release_plan",
            "level": level.rawValue, "platform": platform.rawValue,
            "focusedIndex": focusedIndex as Any? ?? NSNull(),
            "candidates": candidates.map { candidate in
                ["tabID": candidate.tabID.rawValue.uuidString.lowercased(),
                 "inactiveSince": candidate.inactiveSince?.timeIntervalSinceReferenceDate as Any? ?? NSNull(),
                 "keepsPageLoaded": candidate.keepsPageLoaded,
                 "isPresented": candidate.presentedIndex != nil,
                 "presentedIndex": candidate.presentedIndex as Any? ?? NSNull()]
            }
        ]) else { return ([], []) }
        let known = Dictionary(uniqueKeysWithValues: candidates.map {
            ($0.tabID.rawValue.uuidString.lowercased(), $0.tabID)
        })
        func tabIDs(_ field: String) -> [TabID] {
            (response[field] as? [String] ?? []).compactMap { known[$0] }
        }
        return (tabIDs("tabIDs"), tabIDs("fallbackTabIDs"))
    }
    /// Whether a renderer termination is answered by reloading again. An
    /// unavailable core stops reloading instead of risking a crash loop.
    static func processRecoveryAction(consecutiveTerminations: Int) -> BrowserProcessRecoveryAction {
        guard let action = evaluate(["version": 1, "operation": "residency.process_recovery",
            "consecutiveTerminations": consecutiveTerminations])?["action"] as? String else { return .showFailure }
        return action == "reload" ? .reload : .showFailure
    }
    /// What dismissing this tab means. An unavailable core closes the tab, the
    /// one dismissal that never discards a window or a durable page.
    static func tabDismissal(for tab: BrowserTab?, tabCount: Int) -> BrowserTabDismissalAction {
        guard let tab else { return .closeWindow }
        guard let action = evaluate(["version": 1, "operation": "tabs.dismissal",
            "placement": tab.placement.rawValue, "isStartPage": tab.isStartPage,
            "tabCount": tabCount])?["action"] as? String else { return .closeTab }
        switch action {
        case "unloadPage": return .unloadPage
        case "closeWindow": return .closeWindow
        default: return .closeTab
        }
    }
    /// Risk reasons and the confirmation rule for one download. An unavailable
    /// core asks the person before saving rather than guessing the file is safe.
    static func downloadRisk(suggestedFilename: String, sanitizedFilename: String, mimeType: String?,
        extensionRunsCode: Bool, mimeTypeRunsCode: Bool, typesRelated: Bool?,
        isUserInitiated: Bool) -> BrowserDownloadRiskVerdict {
        let response = evaluate([
            "version": 1, "operation": "downloads.risk",
            "suggestedFilename": suggestedFilename, "sanitizedFilename": sanitizedFilename,
            "mimeType": mimeType as Any? ?? NSNull(), "extensionRunsCode": extensionRunsCode,
            "mimeTypeRunsCode": mimeTypeRunsCode, "typesRelated": typesRelated as Any? ?? NSNull(),
            "userInitiated": isUserInitiated
        ])
        let reasons = (response?["reasons"] as? [String] ?? []).compactMap(BrowserDownloadRiskReason.init(rawValue:))
        return BrowserDownloadRiskVerdict(
            assessment: BrowserDownloadRiskAssessment(sanitizedFilename: sanitizedFilename, reasons: reasons),
            requiresConfirmation: response?["requiresConfirmation"] as? Bool ?? true)
    }
    /// The automatic-download action and the page/origin throttle state to
    /// keep. An unavailable core asks the person instead of deciding silently.
    static func automaticDownload(isUserInitiated: Bool, isUserApprovedRetry: Bool,
        savedDecision: BrowserSitePermissionDecision, hasAllowedAutomaticDownload: Bool)
        -> (action: BrowserAutomaticDownloadAction, hasAllowedAutomaticDownload: Bool) {
        guard let response = evaluate([
            "version": 1, "operation": "downloads.automatic",
            "userInitiated": isUserInitiated, "userApprovedRetry": isUserApprovedRetry,
            "savedDecision": savedDecision.rawValue, "hasAllowedAutomaticDownload": hasAllowedAutomaticDownload
        ]), let allowance = response["hasAllowedAutomaticDownload"] as? Bool else {
            return (.requestPermission, hasAllowedAutomaticDownload)
        }
        let action: BrowserAutomaticDownloadAction = switch response["action"] as? String {
        case "allow": .allow
        case "deny": .deny
        default: .requestPermission
        }
        return (action, allowance)
    }
    /// One progress reading. `estimator` is the core's opaque per-transfer
    /// state; pass back what the previous reading returned.
    static func downloadProgress(estimator: [String: Any]?, completedUnitCount: Int64, totalUnitCount: Int64,
        fractionCompleted: Double, isPaused: Bool, uptime: TimeInterval)
        -> (estimator: [String: Any], update: BrowserDownloadTransferUpdate)? {
        guard let response = evaluate([
            "version": 1, "operation": "downloads.progress",
            "estimator": estimator as Any? ?? NSNull(), "completedUnitCount": completedUnitCount,
            "totalUnitCount": totalUnitCount,
            "fractionCompleted": fractionCompleted.isFinite ? fractionCompleted : 0,
            "isPaused": isPaused, "uptime": uptime
        ]), let next = response["estimator"] as? [String: Any],
            let telemetry = (response["telemetry"] as? [String: Any]).flatMap(BrowserDownloadTransferTelemetry.init(coreValues:)),
            let progress = (response["progress"] as? NSNumber)?.doubleValue else { return nil }
        return (next, BrowserDownloadTransferUpdate(telemetry: telemetry, progress: progress))
    }
    /// One bounded policy call. Nil when the core rejects the request or cannot
    /// answer; every caller maps that to its own fail-safe outcome.
    static func evaluate(_ request: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        var length = 0
        let measured = data.withUnsafeBytes {
            crest_core_evaluate_policy($0.bindMemory(to: UInt8.self).baseAddress, data.count, nil, 0, &length)
        }
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= 65_536 else {
            logger.error("Core policy rejected \(request["operation"] as? String ?? "unknown", privacy: .public): \(measured)")
            return nil
        }
        var output = Data(count: length)
        let capacity = length
        let result = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { input in
                crest_core_evaluate_policy(input.bindMemory(to: UInt8.self).baseAddress, data.count,
                    destination.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
            }
        }
        guard result == CREST_OK else {
            logger.error("Core policy output failed: \(result)")
            return nil
        }
        return try? JSONSerialization.jsonObject(with: output) as? [String: Any]
    }
}

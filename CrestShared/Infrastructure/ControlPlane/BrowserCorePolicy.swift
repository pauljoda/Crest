import CrestCoreABI
import Foundation
import os

/// A stateless boundary for synchronous domain decisions. Session mutations
/// remain commands to the core session authority.
enum BrowserCorePolicy {
    // MARK: - Types

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

    /// Every policy request: the version and operation, then the operation's
    /// own members at the same level. The session answers some policies too,
    /// with the same request.
    struct Request<Arguments: Encodable>: Encodable {
        private enum CodingKeys: String, CodingKey {
            case version
            case operation
        }

        let operation: BrowserPolicyOperation
        let arguments: Arguments

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .version)
            try container.encode(operation, forKey: .operation)
            try arguments.encode(to: encoder)
        }
    }

    private struct LinkNavigationRequest: Encodable {
        @BrowserCoreNullable var url: String?
        let userActivatedLink: Bool
        let topLevel: Bool
        var commandModified: Bool?
        var optionModified: Bool?
        var middleClick: Bool?
        var peekModifier: LinkPeekModifier?
        var peekModified: Bool?
        var newTabModified: Bool?
        let shiftModified: Bool
        let focusesNewTabs: Bool
        let hasContext: Bool
        @BrowserCoreNullable var placement: TabPlacement?
        @BrowserCoreNullable var savedUrl: String?
        let automaticallyOpensPeek: Bool
    }

    private struct LinkNavigationAnswer: Decodable {
        let decision: BrowserLinkNavigationDecision
    }

    private struct AddressIntentRequest: Encodable {
        let input: String
        let allowsInternalPages: Bool
        let searchProvider: SearchProviderDescriptor
    }

    private struct AddressIntentAnswer: Decodable {
        let url: String
        @BrowserCoreOptional var searchQuery: String?
    }

    private struct HistoryURLRequest: Encodable {
        let url: String
    }

    private struct URLAnswer: Decodable {
        let url: String
    }

    private struct ReleaseLimitRequest: Encodable {
        let level: MemoryPressureLevel
        let platform: DevicePlatform
        let eligiblePageCount: Int
    }

    private struct ReleaseLimitAnswer: Decodable {
        let limit: Int
    }

    private struct ReleasePlanRequest: Encodable {
        struct Candidate: Encodable {
            let tabID: String
            @BrowserCoreNullable var inactiveSince: TimeInterval?
            let keepsPageLoaded: Bool
            let isPresented: Bool
            @BrowserCoreNullable var presentedIndex: Int?
        }

        let level: MemoryPressureLevel
        let platform: DevicePlatform
        @BrowserCoreNullable var focusedIndex: Int?
        let candidates: [Candidate]
    }

    private struct ReleasePlanAnswer: Decodable {
        @BrowserCoreOptional var tabIDs: [String]?
        @BrowserCoreOptional var fallbackTabIDs: [String]?
    }

    private struct ProcessRecoveryRequest: Encodable {
        let consecutiveTerminations: Int
    }

    private struct ProcessRecoveryAnswer: Decodable {
        @BrowserCoreOptional var action: BrowserProcessRecoveryAction?
    }

    private struct DismissalRequest: Encodable {
        let placement: TabPlacement
        let isStartPage: Bool
        let tabCount: Int
    }

    private struct DismissalAnswer: Decodable {
        @BrowserCoreOptional var action: BrowserTabDismissalAction?
    }

    private struct AutomaticDownloadRequest: Encodable {
        let userInitiated: Bool
        let userApprovedRetry: Bool
        let savedDecision: SitePermissionDecision
        let hasAllowedAutomaticDownload: Bool
    }

    private struct AutomaticDownloadAnswer: Decodable {
        let hasAllowedAutomaticDownload: Bool
        @BrowserCoreOptional var action: BrowserAutomaticDownloadAction?
    }

    // MARK: - Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "CorePolicy")

    // MARK: - Actions - Navigation

    /// The link decision when the core cannot answer. A person's own top-level
    /// click opens a new tab in the same Space, so a pinned or saved tab never
    /// leaves the page it keeps and nothing opens as a Peek or crosses a
    /// profile; a script or subframe navigation keeps the engine's own
    /// in-place behavior, which Crest never intercepts.
    private static func unansweredLinkNavigation(isUserActivatedLink: Bool, isTopLevelNavigation: Bool)
        -> BrowserLinkNavigationDecision
    {
        isUserActivatedLink && isTopLevelNavigation ? .foregroundTab : .navigate
    }

    static func modifiedLinkNavigation(
        destinationURL: URL?, context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool, isTopLevelNavigation: Bool, isCommandModified: Bool,
        isOptionModified: Bool, isMiddleClick: Bool, peekModifier: LinkPeekModifier,
        isShiftModified: Bool, focusesNewTabs: Bool
    ) -> BrowserLinkNavigationDecision {
        let request = LinkNavigationRequest(
            url: destinationURL?.absoluteString, userActivatedLink: isUserActivatedLink,
            topLevel: isTopLevelNavigation, commandModified: isCommandModified, optionModified: isOptionModified,
            middleClick: isMiddleClick, peekModifier: peekModifier, shiftModified: isShiftModified,
            focusesNewTabs: focusesNewTabs, hasContext: context != nil, placement: context?.placement,
            savedUrl: context?.savedURL?.absoluteString,
            automaticallyOpensPeek: context?.automaticallyOpensPeek ?? false)
        guard let answer = evaluate(.navigationModifiedLink, request, answer: LinkNavigationAnswer.self) else {
            return unansweredLinkNavigation(
                isUserActivatedLink: isUserActivatedLink, isTopLevelNavigation: isTopLevelNavigation)
        }
        return answer.decision
    }

    static func linkNavigation(
        destinationURL: URL?, context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool, isTopLevelNavigation: Bool, isPeekModified: Bool,
        isNewTabModified: Bool, isShiftModified: Bool, focusesNewTabs: Bool
    ) -> BrowserLinkNavigationDecision {
        let request = LinkNavigationRequest(
            url: destinationURL?.absoluteString, userActivatedLink: isUserActivatedLink,
            topLevel: isTopLevelNavigation, peekModified: isPeekModified, newTabModified: isNewTabModified,
            shiftModified: isShiftModified, focusesNewTabs: focusesNewTabs, hasContext: context != nil,
            placement: context?.placement, savedUrl: context?.savedURL?.absoluteString,
            automaticallyOpensPeek: context?.automaticallyOpensPeek ?? false)
        guard let answer = evaluate(.navigationLink, request, answer: LinkNavigationAnswer.self) else {
            return unansweredLinkNavigation(
                isUserActivatedLink: isUserActivatedLink, isTopLevelNavigation: isTopLevelNavigation)
        }
        return answer.decision
    }

    static func addressIntent(_ input: String, provider: SearchProvider) -> BrowserAddressIntent? {
        let request = AddressIntentRequest(
            input: input, allowsInternalPages: BrowserEngineRegistration.current.supports(.internalPages),
            searchProvider: SearchProviderDescriptor(provider))
        guard let answer = evaluate(.addressIntent, request, answer: AddressIntentAnswer.self),
            let url = URL(string: answer.url)
        else { return nil }
        if let query = answer.searchQuery { return .search(query: query, provider: provider, url: url) }
        return .open(url)
    }

    static func normalizedHistoryURL(_ url: URL) -> URL? {
        guard
            let answer = evaluate(.historyNormalize, HistoryURLRequest(url: url.absoluteString), answer: URLAnswer.self)
        else { return nil }
        return URL(string: answer.url)
    }

    // MARK: - Actions - Residency

    /// How many eligible pages this squeeze may take back. A core that cannot
    /// answer releases nothing rather than guessing at a budget.
    static func memoryPressureReleaseLimit(
        level: MemoryPressureLevel, eligiblePageCount: Int,
        platform: DevicePlatform
    ) -> Int {
        let request = ReleaseLimitRequest(level: level, platform: platform, eligiblePageCount: eligiblePageCount)
        guard let limit = evaluate(.residencyReleaseLimit, request, answer: ReleaseLimitAnswer.self)?.limit,
            limit >= 0
        else { return 0 }
        return limit
    }

    /// The order in which release should be attempted. The caller still asks
    /// each page's engine for the residency veto and re-validates ownership
    /// after every await; `presentedFallback` is only used when the off-screen
    /// sweep released nobody at all.
    static func residencyReleasePlan(
        level: MemoryPressureLevel, platform: DevicePlatform,
        candidates: [ResidencyCandidate], focusedIndex: Int?
    ) -> (offScreen: [TabID], presentedFallback: [TabID]) {
        let request = ReleasePlanRequest(
            level: level, platform: platform, focusedIndex: focusedIndex,
            candidates: candidates.map { candidate in
                ReleasePlanRequest.Candidate(
                    tabID: candidate.tabID.rawValue.coreIdentifier,
                    inactiveSince: candidate.inactiveSince?.timeIntervalSinceReferenceDate,
                    keepsPageLoaded: candidate.keepsPageLoaded, isPresented: candidate.presentedIndex != nil,
                    presentedIndex: candidate.presentedIndex)
            })
        guard let answer = evaluate(.residencyReleasePlan, request, answer: ReleasePlanAnswer.self) else {
            return ([], [])
        }
        let known = Dictionary(
            uniqueKeysWithValues: candidates.map {
                ($0.tabID.rawValue.coreIdentifier, $0.tabID)
            })
        func tabIDs(_ identifiers: [String]?) -> [TabID] {
            (identifiers ?? []).compactMap { known[$0] }
        }
        return (tabIDs(answer.tabIDs), tabIDs(answer.fallbackTabIDs))
    }

    /// Whether a renderer termination is answered by reloading again. An
    /// unavailable core stops reloading instead of risking a crash loop.
    static func processRecoveryAction(consecutiveTerminations: Int) -> BrowserProcessRecoveryAction {
        evaluate(
            .residencyProcessRecovery, ProcessRecoveryRequest(consecutiveTerminations: consecutiveTerminations),
            answer: ProcessRecoveryAnswer.self)?.action ?? .showFailure
    }

    /// What dismissing this tab means. An unavailable core closes the tab, the
    /// one dismissal that never discards a window or a durable page.
    static func tabDismissal(for tab: BrowserTab?, tabCount: Int) -> BrowserTabDismissalAction {
        guard let tab else { return .closeWindow }
        let request = DismissalRequest(placement: tab.placement, isStartPage: tab.isStartPage, tabCount: tabCount)
        return evaluate(.tabsDismissal, request, answer: DismissalAnswer.self)?.action ?? .closeTab
    }

    // MARK: - Actions - Downloads

    /// The automatic-download action and the page/origin throttle state to
    /// keep. An unavailable core asks the person instead of deciding silently.
    static func automaticDownload(
        isUserInitiated: Bool, isUserApprovedRetry: Bool,
        savedDecision: SitePermissionDecision, hasAllowedAutomaticDownload: Bool
    ) -> (action: BrowserAutomaticDownloadAction, hasAllowedAutomaticDownload: Bool) {
        let request = AutomaticDownloadRequest(
            userInitiated: isUserInitiated, userApprovedRetry: isUserApprovedRetry, savedDecision: savedDecision,
            hasAllowedAutomaticDownload: hasAllowedAutomaticDownload)
        guard let answer = evaluate(.downloadsAutomatic, request, answer: AutomaticDownloadAnswer.self) else {
            return (.requestPermission, hasAllowedAutomaticDownload)
        }
        return (answer.action ?? .requestPermission, answer.hasAllowedAutomaticDownload)
    }

    // MARK: - Actions - Evaluation

    /// One bounded policy call. Nil when the request cannot be encoded, the core
    /// rejects it or cannot answer, or the answer does not decode; every caller
    /// maps that to its own fail-safe outcome.
    static func evaluate<Arguments: Encodable, Answer: Decodable>(
        _ operation: BrowserPolicyOperation, _ arguments: Arguments, answer: Answer.Type
    ) -> Answer? {
        guard let data = try? JSONEncoder().encode(Request(operation: operation, arguments: arguments)) else {
            return nil
        }
        guard let output = evaluate(data, operation: operation) else { return nil }
        return try? JSONDecoder().decode(Answer.self, from: output)
    }

    /// A policy call without members of its own.
    static func evaluate<Answer: Decodable>(_ operation: BrowserPolicyOperation, answer: Answer.Type) -> Answer? {
        evaluate(operation, BrowserCoreNoArguments(), answer: answer)
    }

    private static func evaluate(_ data: Data, operation: BrowserPolicyOperation) -> Data? {
        var length = 0
        let measured = data.withUnsafeBytes {
            crest_core_evaluate_policy($0.bindMemory(to: UInt8.self).baseAddress, data.count, nil, 0, &length)
        }
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= 65_536 else {
            logger.error("Core policy rejected \(operation.rawValue, privacy: .public): \(measured)")
            return nil
        }
        var output = Data(count: length)
        let capacity = length
        let result = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { input in
                crest_core_evaluate_policy(
                    input.bindMemory(to: UInt8.self).baseAddress, data.count,
                    destination.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
            }
        }
        guard result == CREST_OK else {
            logger.error("Core policy output failed: \(result)")
            return nil
        }
        return output
    }
}

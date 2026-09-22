import CrestCoreABI
import Foundation
import os

/// A stateless boundary for synchronous domain decisions. Session mutations
/// remain commands to the core session authority.
enum BrowserCorePolicy {
    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "CorePolicy")
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
            let decision = BrowserLinkNavigationDecision(rawValue: value) else { return .navigate }
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
            let decision = BrowserLinkNavigationDecision(rawValue: value) else { return .navigate }
        return decision
    }
    static func addressIntent(_ input: String, provider: BrowserSearchProvider) -> BrowserAddressIntent? {
        #if CREST_CHROMIUM_HOST
        let allowsInternalPages = true
        #else
        let allowsInternalPages = false
        #endif
        guard let response = evaluate([
            "version": 1, "operation": "address.intent", "input": input,
            "allowsInternalPages": allowsInternalPages,
            "searchTemplate": provider.coreSearchURLTemplate
        ]), let text = response["url"] as? String, let url = URL(string: text) else { return nil }
        if let query = response["searchQuery"] as? String { return .search(query: query, provider: provider, url: url) }
        return .open(url)
    }
    static func normalizedHistoryURL(_ url: URL) -> URL? {
        guard let text = evaluate(["version": 1, "operation": "history.normalize", "url": url.absoluteString])?["url"] as? String
        else { return nil }
        return URL(string: text)
    }
    static func recordVisit(url: URL, title: String?, at date: Date, previous: BrowserHistoryEntry?)
        -> (entry: BrowserHistoryEntry, maximumEntries: Int)? {
        var request: [String: Any] = ["version": 1, "operation": "history.visit", "url": url.absoluteString,
            "title": title as Any? ?? NSNull(), "now": date.timeIntervalSince1970, "newId": UUID().uuidString.lowercased()]
        if let previous {
            request["previous"] = ["id": previous.id.uuidString.lowercased(), "url": previous.url.absoluteString,
                "title": previous.title, "firstVisitedAt": previous.firstVisitedAt.timeIntervalSince1970,
                "lastVisitedAt": previous.lastVisitedAt.timeIntervalSince1970, "visitCount": previous.visitCount]
        }
        guard let response = evaluate(request), let record = response["entry"] as? [String: Any],
            let maximum = response["maximumEntries"] as? Int, maximum > 0,
            let bytes = try? JSONSerialization.data(withJSONObject: record) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        guard let entry = try? decoder.decode(BrowserHistoryEntry.self, from: bytes) else { return nil }
        return (entry, maximum)
    }
    static func expiredIndices(dates: [Date], now: Date, lifetime: TimeInterval) -> IndexSet? {
        recordIndices(dates: dates, operation: "records.expired", parameters: [
            "now": now.timeIntervalSinceReferenceDate, "lifetime": lifetime
        ])
    }
    static func historyIndices(dates: [Date], from start: Date, until end: Date) -> IndexSet? {
        recordIndices(dates: dates, operation: "history.remove_range", parameters: [
            "start": start.timeIntervalSinceReferenceDate, "end": end.timeIntervalSinceReferenceDate
        ])
    }
    private static func recordIndices(dates: [Date], operation: String, parameters: [String: Double]) -> IndexSet? {
        var result = IndexSet()
        for start in stride(from: 0, to: dates.count, by: 512) {
            let end = min(start + 512, dates.count)
            var request: [String: Any] = parameters
            request["version"] = 1
            request["operation"] = operation
            request["timestamps"] = dates[start..<end].map(\.timeIntervalSinceReferenceDate)
            guard let values = evaluate(request)?["indices"] as? [Int],
                Set(values).count == values.count,
                values.allSatisfy({ $0 >= 0 && $0 < end - start }) else { return nil }
            values.forEach { result.insert(start + $0) }
        }
        return result
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
    private static func evaluate(_ request: [String: Any]) -> [String: Any]? {
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

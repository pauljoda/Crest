#if CREST_CORE_BACKED
import CrestCoreABI
import Foundation
import os

/// A stateless boundary for synchronous domain decisions. Session mutations
/// remain commands to the core session authority.
enum BrowserCorePolicy {
    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "CorePolicy")
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
#endif

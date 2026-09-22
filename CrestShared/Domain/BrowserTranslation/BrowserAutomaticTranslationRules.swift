import Foundation

/// Explicit source-language choices, persisted as this value's JSON. The
/// portable core decides which rule applies, which target it yields and how an
/// edit replaces region aliases; an unavailable core never translates.
struct BrowserAutomaticTranslationRules: Codable, Equatable, Sendable {
    struct Rule: Codable, Equatable, Sendable {
        var targetID: String
        var isEnabled: Bool
    }

    private(set) var sources: [String: Rule] = [:]

    init(rawValue: String = "") {
        self =
            rawValue.data(using: .utf8).flatMap {
                try? JSONDecoder().decode(Self.self, from: $0)
            } ?? Self(sources: [:])
    }

    private init(sources: [String: Rule]) { self.sources = sources }

    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func rule(for sourceID: String) -> Rule? {
        BrowserCorePolicy.translationRule(in: self, sourceID: sourceID)?.rule
    }

    func target(for sourceID: String) -> String? {
        BrowserCorePolicy.translationRule(in: self, sourceID: sourceID)?.target
    }

    mutating func set(sourceID: String, targetID: String, isEnabled: Bool) {
        guard let updated = BrowserCorePolicy.settingTranslationRule(
            in: self, sourceID: sourceID, targetID: targetID, isEnabled: isEnabled)
        else { return }
        sources = updated
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        BrowserCorePolicy.languageMatches(lhs, candidates: [rhs])?.first ?? false
    }

    /// `matches(language, candidate)` for each candidate, in one core call.
    static func matches(_ language: String, in candidates: [String]) -> [Bool] {
        BrowserCorePolicy.languageMatches(language, candidates: candidates)
            ?? Array(repeating: false, count: candidates.count)
    }
}

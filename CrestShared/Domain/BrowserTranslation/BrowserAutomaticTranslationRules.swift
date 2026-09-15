import Foundation

/// Explicit source-language choices. Missing, disabled, or invalid rules never
/// fall back to translating every language into the device language.
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
        if let exact = sources[sourceID] { return exact }
        return sources.keys.sorted().first { Self.matches($0, sourceID) }.flatMap { sources[$0] }
    }

    func target(for sourceID: String) -> String? {
        guard let rule = rule(for: sourceID), rule.isEnabled,
            !sourceID.isEmpty, !rule.targetID.isEmpty, !Self.matches(sourceID, rule.targetID)
        else { return nil }
        return rule.targetID
    }

    mutating func set(sourceID: String, targetID: String, isEnabled: Bool) {
        guard !sourceID.isEmpty else { return }
        // Region aliases share a choice; distinct scripts retain separate rules.
        for key in sources.keys.filter({ Self.matches($0, sourceID) }) { sources.removeValue(forKey: key) }
        sources[sourceID] = Rule(targetID: targetID, isEnabled: isEnabled)
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let left = Locale.Language(identifier: lhs)
        let right = Locale.Language(identifier: rhs)
        return left.languageCode != nil && left.languageCode == right.languageCode && left.script == right.script
    }
}

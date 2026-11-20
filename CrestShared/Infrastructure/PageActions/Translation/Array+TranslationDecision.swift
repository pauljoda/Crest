import Foundation

extension Array where Element == TranslationRule {
    // MARK: - Actions - Deciding

    /// What the core decides for pages in `sourceID` under these rules, for
    /// a person whose first language is `preferredID`: the rule that applies,
    /// the language it translates to, and whether such pages are offered
    /// translation. Rules the core refuses never translate, and a core that
    /// cannot answer decides nothing.
    func decision(for sourceID: String, preferring preferredID: String? = nil) -> TranslationDecision? {
        try? CrestCore.answer(TranslationChoice(rules: self, sourceLanguage: sourceID, preferredLanguage: preferredID))
    }
}

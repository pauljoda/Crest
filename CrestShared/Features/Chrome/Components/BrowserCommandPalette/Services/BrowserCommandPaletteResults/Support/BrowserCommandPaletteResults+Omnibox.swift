import Foundation

extension BrowserCommandPaletteResults {
    /// The rows shown while the address bar belongs to a keyword provider.
    ///
    /// Keyword mode replaces the ordinary sources rather than joining them, the
    /// way Chrome's does: once the person has handed the query to an extension,
    /// mixing in tab and history matches for the raw text would be noise.
    static func omniboxResults(
        for context: BrowserCommandPaletteOmniboxContext
    ) -> [BrowserCommandPaletteResult] {
        var results = [defaultResult(for: context)]

        for (index, suggestion) in context.suggestions
            .prefix(BrowserCommandPaletteResultLimits.omniboxSuggestions)
            .enumerated()
        {
            guard !Task.isCancelled else { return results }
            results.append(
                BrowserCommandPaletteResult(
                    section: .omnibox,
                    id: "omnibox.\(context.keyword.rawValue).\(index)",
                    title: suggestion.description,
                    subtitle: suggestion.content,
                    symbol: omniboxSymbol,
                    trailing: "",
                    target: .omniboxSuggestion(
                        BrowserOmniboxAcceptance(
                            keyword: context.keyword,
                            content: suggestion.content,
                            isDeletable: suggestion.isDeletable
                        )
                    )
                )
            )
        }

        return results
    }

    /// Substitutes Chrome's `%s` placeholder in a default-suggestion line.
    static func omniboxDefaultDescription(
        for context: BrowserCommandPaletteOmniboxContext
    ) -> String {
        let template = context.defaultSuggestionDescription
        guard !template.isEmpty else { return context.title }
        return template.replacingOccurrences(of: "%s", with: context.query)
    }

    private static var omniboxSymbol: String { "puzzlepiece.extension" }

    private static func defaultResult(
        for context: BrowserCommandPaletteOmniboxContext
    ) -> BrowserCommandPaletteResult {
        BrowserCommandPaletteResult(
            section: .omnibox,
            id: "omnibox.\(context.keyword.rawValue).default",
            title: omniboxDefaultDescription(for: context),
            subtitle: context.title,
            symbol: omniboxSymbol,
            trailing: "",
            target: .omniboxSuggestion(
                BrowserOmniboxAcceptance(
                    keyword: context.keyword,
                    content: context.query
                )
            )
        )
    }
}

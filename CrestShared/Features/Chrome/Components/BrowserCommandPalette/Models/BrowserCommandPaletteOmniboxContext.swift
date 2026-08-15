import Foundation

/// Everything the result pipeline needs to render keyword mode, flattened into
/// values.
///
/// The provider itself never reaches the pipeline: results are prepared on a
/// detached task, and a `BrowserOmniboxSuggesting` is main-actor isolated. The
/// model resolves the provider, awaits its suggestions, and sends only the
/// answers across.
struct BrowserCommandPaletteOmniboxContext: Equatable, Sendable {
    let keyword: BrowserOmniboxKeyword
    /// The text after the keyword, which is what the provider was asked about.
    let query: String
    /// The provider's display name.
    let title: String
    /// The provider's default suggestion line, before `%s` substitution.
    let defaultSuggestionDescription: String
    let suggestions: [BrowserOmniboxSuggestion]
}

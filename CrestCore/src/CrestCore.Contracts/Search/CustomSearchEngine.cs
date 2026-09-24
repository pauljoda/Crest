namespace CrestCore.Contracts;

/// A Space's custom search engine as the person typed it or as it is stored.
/// Each template holds exactly one `%s` or `{searchTerms}` query placeholder;
/// an absent suggestion template means the engine offers no suggestions.
public sealed record CustomSearchEngine(Guid Id, string Name, string SearchTemplate, string? SuggestionTemplate);

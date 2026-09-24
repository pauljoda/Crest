namespace CrestCore.Contracts;

/// <summary>A search engine a person added to a Space. A template holds exactly one
/// `%s` or `{searchTerms}` placeholder for the query.</summary>
public sealed record CustomSearchProvider(Guid Id, string Name, string SearchUrlTemplate, string? SuggestionUrlTemplate);

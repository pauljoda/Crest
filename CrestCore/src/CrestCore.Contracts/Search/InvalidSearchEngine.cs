namespace CrestCore.Contracts;

/// A custom search engine has `Flaw`, the first rule it breaks.
public sealed record InvalidSearchEngine(SearchEngineFlaw Flaw) : Rejection;

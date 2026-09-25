namespace CrestCore.Contracts;

/// Finds the next match of `Query` in the page, wrapping at its end, and
/// answers `FindFinished` once the engine has counted. An empty query clears
/// the page's matches. False when the page cannot search.
public sealed record FindInPage(Guid PageId, string Query, bool Backwards, bool CaseSensitive) : PageRequest<bool>;

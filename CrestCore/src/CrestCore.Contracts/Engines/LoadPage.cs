namespace CrestCore.Contracts;

/// Loads `Url` in a page, as the core resolved it from what the person asked
/// for. The load is the app's own rather than the page content's, so it may
/// reach an address web content may not. The binding reports the navigation
/// it starts as it reports any other.
public sealed record LoadPage(Guid PageId, string Url) : EngineCommand;

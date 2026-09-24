namespace CrestCore.Contracts;

/// Asks a page to load what the person typed or chose: an address, or words
/// the Space's search engine looks up. The core resolves `Input` by the
/// address rules of the page's Space and engine, shows the page heading there
/// and asks the page's engine to load it. Refused when the page is not open or
/// its engine holds no page to load into, its Space is locked or being
/// deleted, or `Input` names nothing a page can load, as blank input does.
public sealed record Navigate(Guid PageId, string Input) : PageIntent;

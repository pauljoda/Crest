namespace CrestCore.Contracts;

/// The icon the engine found for the document the page shows, which the
/// page's tab takes once the core assigns it.
public sealed record PageIcon(Guid PageId) : PageRequest<PageIconImage>;

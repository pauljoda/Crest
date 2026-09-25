namespace CrestCore.Contracts;

/// The page's view is on screen and takes focus.
public sealed record ShowPage(Guid PageId) : PageRequest<bool>;

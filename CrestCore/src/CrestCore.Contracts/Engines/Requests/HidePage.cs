namespace CrestCore.Contracts;

/// The page's view left the screen.
public sealed record HidePage(Guid PageId) : PageRequest<bool>;

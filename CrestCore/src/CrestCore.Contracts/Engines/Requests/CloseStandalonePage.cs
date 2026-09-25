namespace CrestCore.Contracts;

/// Closes a page `OpenStandalonePage` opened.
public sealed record CloseStandalonePage(Guid PageId) : PageRequest<bool>;

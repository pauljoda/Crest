namespace CrestCore.Contracts;

/// Stops what the page is loading.
public sealed record StopLoading(Guid PageId) : PageRequest<bool>;

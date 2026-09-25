namespace CrestCore.Contracts;

/// Reloads the page's document, fetching it again from its origin when
/// `BypassesCache`.
public sealed record ReloadPage(Guid PageId, bool BypassesCache) : PageRequest<bool>;

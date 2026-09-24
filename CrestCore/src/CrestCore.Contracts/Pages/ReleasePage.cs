namespace CrestCore.Contracts;

/// Its owner is done with a page. The page is gone at once, and its engine is
/// asked to close what it still holds. `KeepsState` says the owner kept what it
/// needs to bring the page back.
public sealed record ReleasePage(Guid PageId, bool KeepsState) : PageIntent;

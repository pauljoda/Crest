namespace CrestCore.Contracts;

/// Closes the engine's page for a page its owner released. `KeepsState` says
/// the owner kept what it needs to bring the page back later, so the page was
/// unloaded rather than closed for good. The binding answers with `PageClosed`.
public sealed record ClosePage(Guid PageId, bool KeepsState) : EngineCommand;

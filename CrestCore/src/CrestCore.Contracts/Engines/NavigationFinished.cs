namespace CrestCore.Contracts;

/// A page's navigation finished at `Url`, titled `Title`, which may be empty.
/// The core records the first finish of each document: the tab that owns the
/// page shows the address and title, and the Space's history holds a visit. A
/// move within the document finishes once its title settles.
public sealed record NavigationFinished(Guid PageId, string Url, string Title) : EngineEvent;

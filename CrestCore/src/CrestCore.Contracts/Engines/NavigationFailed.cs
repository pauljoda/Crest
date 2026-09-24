namespace CrestCore.Contracts;

/// A page's navigation to `Url` failed with `Error`, so the document it was
/// loading records nothing.
public sealed record NavigationFailed(Guid PageId, string? Url, NavigationError Error) : EngineEvent;

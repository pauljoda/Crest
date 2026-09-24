namespace CrestCore.Contracts;

/// A page's navigation failed as `Failure` describes, so the document it was
/// loading records nothing, and the page shows the failure until another
/// navigation begins.
public sealed record NavigationFailed(Guid PageId, PageFailure Failure) : EngineEvent;

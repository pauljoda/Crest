namespace CrestCore.Contracts;

/// Keeps a Quick Window's page, `PageId`, in its Space's archive as a closed
/// open tab at the address and title it shows, so it can be found again. The
/// page may already be gone, as one memory pressure took back is; the core
/// keeps what it showed last. A page still open must live in `SpaceId`.
/// Refused when the page was already kept or archived, when it lives in
/// another Space, when the core no longer knows it, and when the Space is
/// locked or being deleted.
public sealed record ArchiveTransientPage(Guid WorkspaceId, Guid PageId, Guid SpaceId) : SessionIntent(WorkspaceId);

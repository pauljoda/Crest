namespace CrestCore.Contracts;

/// Keeps a Quick Window's page, `PageId`, in its Space's archive as a closed
/// open tab, so it can be found again. The page may already be gone, as one
/// memory pressure took back is; a page still open must live in `SpaceId`.
/// Refused when the page was already kept or archived, when it lives in
/// another Space, and when the Space is locked or being deleted.
///
/// `Address` and `Title` are TRANSITIONAL until WP C slice (c) keeps each
/// page's live state in `Pages`: they say where the page is and what it is
/// called, which the platform reports until the core reads them from the page.
public sealed record ArchiveTransientPage(Guid WorkspaceId, Guid PageId, Guid SpaceId, string Address, string? Title)
    : SessionIntent(WorkspaceId);

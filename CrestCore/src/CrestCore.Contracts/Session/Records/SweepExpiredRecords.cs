namespace CrestCore.Contracts;

/// Applies every Space's retention: open tabs unused for longer than the
/// Space's cleanup lifetime move to its archive, and history and archive
/// entries older than the Space keeps them are removed. A tab a window shows,
/// or a saved window will show, stays open. Locked Spaces are swept too, since
/// a sweep reveals nothing; Spaces being deleted are not.
///
/// Every window of a workspace asks for sweeps, so a sweep less than a minute
/// after the last one does nothing, unless a Space's retention changed since.
public sealed record SweepExpiredRecords(Guid WorkspaceId) : SessionIntent(WorkspaceId);

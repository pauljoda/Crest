namespace CrestCore.Contracts;

/// Opens a workspace of `Kind` that this device's windows may show, and
/// publishes `WorkspaceOpened` with the identity the core gave it and its
/// whole session.
///
/// Without a seed, a kind that keeps a file opens the session the core keeps
/// in its file, as it loaded and repaired it: that session is saved on every
/// edit and syncs through the journal kept beside it. A tab the repair gave a
/// new identity follows as `TabCopied` from the tab whose image it wears. The
/// file's session opens once per launch; opening it again while it is open
/// publishes its `WorkspaceOpened` again. Any other kind starts from the Space
/// template of its kind, such as the one Space a private workspace starts with.
///
/// `Seed` is a session in the stored format, for launches without a file
/// (isolated runs, previews, tests). It opens repaired as the file's session
/// does, with `TabCopied` for each tab the repair gave a new identity. A
/// seeded workspace keeps nothing: it is never saved or synced.
///
/// Refused with `BorrowedWorkspaceRequiresSpace` for a kind that opens only by
/// borrowing, `NoStoredSession` when the core keeps no file or its file holds
/// no session yet (`AdoptLegacySession` gives it its first), `StoredSessionClosed`
/// once the file's session was closed, and `InvalidSession` for a seed the core
/// cannot hold.
[MessageLimit(64 * 1024 * 1024)]
public sealed record OpenWorkspace(WorkspaceKind Kind, byte[]? Seed) : WorkspaceIntent;

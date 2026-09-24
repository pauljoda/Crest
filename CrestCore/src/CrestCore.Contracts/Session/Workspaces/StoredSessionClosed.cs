namespace CrestCore.Contracts;

/// The session the core keeps in its file was opened and closed in this
/// launch. It takes no edits again until the next launch opens the file.
public sealed record StoredSessionClosed : Rejection;

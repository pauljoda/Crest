namespace CrestCore.Contracts;

/// <summary>A workspace joined this device: its kind and the whole session it holds.
/// Every later change to that session names <see cref="WorkspaceId"/>.</summary>
public sealed record WorkspaceOpened(Guid WorkspaceId, WorkspaceKind Kind, SessionState Session) : Change;

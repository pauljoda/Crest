namespace CrestCore.Contracts;

/// A workspace of this kind opens only by borrowing a Space of the workspace
/// that owns it, with `BorrowSpace`.
public sealed record BorrowedWorkspaceRequiresSpace(WorkspaceKind Kind) : Rejection;

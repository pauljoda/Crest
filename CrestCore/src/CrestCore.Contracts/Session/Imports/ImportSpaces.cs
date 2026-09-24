namespace CrestCore.Contracts;

/// Adds each Space of `Spaces` after the workspace's own, whole: its tabs,
/// folders, splits, archive and history. Pinned tabs past the limit become
/// saved tabs. The window shows the first of them, on its first tab.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ImportSpaces(Guid WorkspaceId, Guid WindowId, byte[] Spaces) : ImportWorkspace(WorkspaceId, WindowId);

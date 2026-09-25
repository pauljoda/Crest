namespace CrestCore.Contracts;

/// <summary>
/// A Space's sidebar lists changed. Each list in <see cref="Lists"/> replaces the list of
/// its section's top level, or of its folder's inside, and the lists of
/// <see cref="RemovedFolderIds"/> are gone with their folders. Every other list is as it
/// was. A Space that arrives whole carries its whole outline instead.
/// </summary>
public sealed record SidebarChanged(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<SidebarList> Lists,
    IReadOnlyList<Guid> RemovedFolderIds) : Change;

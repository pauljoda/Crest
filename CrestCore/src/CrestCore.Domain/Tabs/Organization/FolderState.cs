namespace CrestCore.Domain;

public sealed record FolderState(FolderId Id, string Name, TabPlacement Location,
    FolderId? ParentId, bool IsCollapsed, DateTimeOffset? CollapseModifiedAt = null, TabId? OrderAnchorTabId = null);

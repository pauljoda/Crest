namespace CrestCore.Domain;

public sealed record FolderState(Guid Id, string Name, TabPlacement Location,
    Guid? ParentId, bool IsCollapsed, DateTimeOffset? CollapseModifiedAt = null, Guid? OrderAnchorTabId = null);

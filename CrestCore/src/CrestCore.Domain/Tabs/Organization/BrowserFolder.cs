namespace CrestCore.Domain;

public sealed record BrowserFolder(FolderId Id, string Name, TabPlacement Location = TabPlacement.Saved,
    FolderId? ParentId = null, bool IsCollapsed = false, DateTimeOffset? CollapseModifiedAt = null, TabId? OrderAnchorTabId = null);

namespace CrestCore.Domain;

public sealed record BrowserFolder(Guid Id, string Name, TabPlacement Location = TabPlacement.Saved,
    Guid? ParentId = null, bool IsCollapsed = false, DateTimeOffset? CollapseModifiedAt = null, Guid? OrderAnchorTabId = null);

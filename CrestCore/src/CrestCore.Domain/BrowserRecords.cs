namespace CrestCore.Domain;

public sealed record BrowserFolder(FolderId Id, string Name, TabPlacement Location = TabPlacement.Saved,
    FolderId? ParentId = null, bool IsCollapsed = false, DateTimeOffset? CollapseModifiedAt = null, TabId? OrderAnchorTabId = null);
public sealed record ArchivedTab(TabState Tab, DateTimeOffset ClosedAt, string Reason) {
    public TabId Id => Tab.Id;
}
public sealed record HistoryVisit(Guid Id, string Url, string Title, DateTimeOffset FirstVisitedAt,
    DateTimeOffset VisitedAt, int VisitCount);

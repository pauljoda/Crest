namespace CrestCore.Domain;

public sealed record ArchivedTab(TabState Tab, DateTimeOffset ClosedAt, string Reason) {
    public TabId Id => Tab.Id;
}

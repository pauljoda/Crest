namespace CrestCore.Domain;

public sealed record ArchivedTab(TabState Tab, DateTimeOffset ClosedAt, string Reason) {
    #region Variables

    public TabId Id => Tab.Id;

    #endregion
}

namespace CrestCore.Domain;

public sealed record ArchivedTab(TabState Tab, DateTimeOffset ClosedAt, string Reason) {
    #region Variables

    public Guid Id => Tab.Id;

    #endregion
}

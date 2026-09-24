namespace CrestCore.Domain;

/// The one blocked-popup indication a document may show. The `popups.notice`
/// policy spells a status as its `Name`.
public sealed class BlockedPopupStatus {
    #region Variables

    public static readonly BlockedPopupStatus Blocked = new(name: "blocked");
    public static readonly BlockedPopupStatus AllowedAwaitingRetry = new(name: "allowedAwaitingRetry");

    public static IReadOnlyList<BlockedPopupStatus> All { get; } = [Blocked, AllowedAwaitingRetry];

    public string Name { get; }

    #endregion

    #region Constructors

    private BlockedPopupStatus(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static BlockedPopupStatus? Named(string? name) => All.FirstOrDefault(status => status.Name == name);

    #endregion
}

namespace CrestCore.Domain;

/// What dismissing the selected tab does. The `tabs.dismissal` policy spells
/// an action as its `Name`.
public sealed class TabDismissalAction {
    #region Variables

    public static readonly TabDismissalAction UnloadPage = new(name: "unloadPage");
    public static readonly TabDismissalAction CloseTab = new(name: "closeTab");
    public static readonly TabDismissalAction CloseWindow = new(name: "closeWindow");

    public static IReadOnlyList<TabDismissalAction> All { get; } = [UnloadPage, CloseTab, CloseWindow];

    public string Name { get; }

    #endregion

    #region Constructors

    private TabDismissalAction(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static TabDismissalAction? Named(string? name) => All.FirstOrDefault(action => action.Name == name);

    #endregion
}

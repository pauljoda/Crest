namespace CrestCore.Contracts;

/// Where the settings list a filter list. Groups are listed in `All` order.
public sealed class FilterListGroup {
    #region Static Variables

    public static readonly FilterListGroup Ads = new(name: "ads", title: "Ads and Trackers");
    public static readonly FilterListGroup Regional = new(name: "regional", title: "Regional");
    public static readonly FilterListGroup Annoyances = new(name: "annoyances", title: "Annoyances");

    public static IReadOnlyList<FilterListGroup> All { get; } = [Ads, Regional, Annoyances];

    #endregion

    #region Variables

    public string Name { get; }

    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private FilterListGroup(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static FilterListGroup? Named(string? name) => All.FirstOrDefault(group => group.Name == name);

    #endregion
}

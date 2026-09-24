namespace CrestCore.Contracts;

/// The ordered collection a numbered shortcut selects from: the tabs in
/// sidebar order, or the Spaces. JSON policy answers spell it as its `Name`.
public sealed class NumberedSelectionTarget {
    #region Variables

    public static readonly NumberedSelectionTarget Tab = new(name: "tab");
    public static readonly NumberedSelectionTarget Space = new(name: "space");

    public static IReadOnlyList<NumberedSelectionTarget> All { get; } = [Tab, Space];

    public string Name { get; }

    #endregion

    #region Constructors

    private NumberedSelectionTarget(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static NumberedSelectionTarget? Named(string? name) => All.FirstOrDefault(target => target.Name == name);

    #endregion
}

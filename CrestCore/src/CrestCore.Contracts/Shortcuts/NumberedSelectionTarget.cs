namespace CrestCore.Contracts;

/// The ordered collection a numbered shortcut selects from: the tabs in
/// sidebar order, or the Spaces. JSON policy answers spell it as its `Name`.
public sealed class NumberedSelectionTarget {
    #region Types

    /// Each platform selects a tab or a Space with its own code, so the one
    /// place that selects switches over the kind.
    public enum Kinds { Tab, Space }

    #endregion

    #region Variables

    public static readonly NumberedSelectionTarget Tab = new(Kinds.Tab, name: "tab");
    public static readonly NumberedSelectionTarget Space = new(Kinds.Space, name: "space");

    public static IReadOnlyList<NumberedSelectionTarget> All { get; } = [Tab, Space];

    public Kinds Kind { get; }
    public string Name { get; }

    #endregion

    #region Constructors

    private NumberedSelectionTarget(Kinds kind, string name) {
        Kind = kind;
        Name = name;
    }

    #endregion

    #region Actions - Lookup

    public static NumberedSelectionTarget? Named(string? name) => All.FirstOrDefault(target => target.Name == name);

    #endregion
}

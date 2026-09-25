namespace CrestCore.Contracts;

/// The ordered collection a numbered shortcut selects from: the tabs in
/// sidebar order, or the Spaces.
public sealed class NumberedSelectionTarget {
    #region Types

    /// Each platform selects a tab or a Space with its own code, so the one
    /// place that selects switches over the kind.
    public enum Kinds { Tab, Space }

    #endregion

    #region Variables

    public static readonly NumberedSelectionTarget Tab = new(Kinds.Tab, name: "tab", counting: question => question.TabCount);
    public static readonly NumberedSelectionTarget Space = new(Kinds.Space, name: "space", counting: question => question.SpaceCount);

    public static IReadOnlyList<NumberedSelectionTarget> All { get; } = [Tab, Space];

    public Kinds Kind { get; }
    public string Name { get; }

    /// How many items a numbered selection question says there are to select from.
    private readonly Func<NumberedSelections, int> counting;

    #endregion

    #region Constructors

    private NumberedSelectionTarget(Kinds kind, string name, Func<NumberedSelections, int> counting) {
        Kind = kind;
        Name = name;
        this.counting = counting;
    }

    #endregion

    #region Actions - Lookup

    public static NumberedSelectionTarget? Named(string? name) => All.FirstOrDefault(target => target.Name == name);

    /// How many items `question` says there are to select from.
    public int Count(NumberedSelections question) => counting(question);

    #endregion
}

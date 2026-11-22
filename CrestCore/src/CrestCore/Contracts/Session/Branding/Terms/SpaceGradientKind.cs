namespace CrestCore.Contracts;

/// How a Space's gradient runs: along a line at its angle, out from the
/// middle, or around the middle starting at its angle. A build that can't
/// name a kind draws the gradient along a line.
public sealed class SpaceGradientKind {
    #region Types

    /// Each kind is drawn with a different gradient, so the code that draws a
    /// sidebar switches over the kind.
    public enum Kinds { Linear, Radial, Angular }

    #endregion

    #region Variables

    public static readonly SpaceGradientKind Linear = new(Kinds.Linear, "linear", "Linear");
    public static readonly SpaceGradientKind Radial = new(Kinds.Radial, "radial", "Radial");
    public static readonly SpaceGradientKind Angular = new(Kinds.Angular, "angular", "Angular");

    public static IReadOnlyList<SpaceGradientKind> All { get; } = [Linear, Radial, Angular];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The kind's name where a person picks it.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SpaceGradientKind(Kinds kind, string name, string title) {
        Kind = kind;
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SpaceGradientKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}

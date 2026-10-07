namespace CrestCore.Contracts;

/// What a crest's custom figure is drawn from.
public sealed class CrestChargeKind {
    #region Types

    /// A figure of each kind is made and drawn from different parts, so the code that makes or draws one switches over the kind.
    public enum Kinds { Heraldic, System, Emoji, Monogram, None }

    #endregion

    #region Variables

    public static readonly CrestChargeKind Heraldic = new(Kinds.Heraldic, "heraldic", "Heraldry", true, true);
    public static readonly CrestChargeKind System = new(Kinds.System, "system", "SF Symbol", true, true);
    public static readonly CrestChargeKind Emoji = new(Kinds.Emoji, "emoji", "Emoji", false, false);
    public static readonly CrestChargeKind Monogram = new(Kinds.Monogram, "monogram", "Monogram", true, true);
    public static readonly CrestChargeKind None = new(Kinds.None, "none", "None", false, false);

    public static IReadOnlyList<CrestChargeKind> All { get; } = [Heraldic, System, Emoji, Monogram, None];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The choice's name where a person picks it.
    [Localized]
    public string Title { get; }

    /// Whether the figure is painted in the crest's emblem color; an emoji keeps its own colors.
    public bool IsTinted { get; }

    /// Whether the figure is drawn in a stroke weight a person can choose.
    public bool TakesWeight { get; }

    #endregion

    #region Constructors

    private CrestChargeKind(Kinds kind, string name, string title, bool isTinted, bool takesWeight) {
        Kind = kind;
        Name = name;
        Title = title;
        IsTinted = isTinted;
        TakesWeight = takesWeight;
    }

    #endregion

    #region Actions - Lookup

    public static CrestChargeKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}

namespace CrestCore.Contracts;

/// How a password Crest makes reads: Crest's grouped style where the site
/// allows it, or random characters with symbols. A member travels as its index
/// in `All`, so `All` is append-only.
public sealed class PasswordStyle {
    #region Static Variables

    public static readonly PasswordStyle Grouped = new(name: "grouped", prefersGroups: true);
    public static readonly PasswordStyle Random = new(name: "random", prefersGroups: false);

    public static IReadOnlyList<PasswordStyle> All { get; } = [Grouped, Random];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether the style asks for the grouped form, which the site's rules may
    /// still rule out.
    internal bool PrefersGroups { get; }

    #endregion

    #region Constructors

    private PasswordStyle(string name, bool prefersGroups) {
        Name = name;
        PrefersGroups = prefersGroups;
    }

    #endregion
}

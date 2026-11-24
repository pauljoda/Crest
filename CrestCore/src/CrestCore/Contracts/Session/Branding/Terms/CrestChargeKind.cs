namespace CrestCore.Contracts;

/// What a crest's custom figure is drawn from.
public sealed class CrestChargeKind {
    #region Types

    /// A figure of each kind is made and drawn from different parts, so the code that makes or draws one switches over the kind.
    public enum Kinds { Heraldic, System, Emoji, Monogram, None }

    #endregion

    #region Static Variables

    /// The most letters a monogram figure shows.
    private const int MaximumMonogramLength = 2;

    /// A heraldic figure, stored as its symbol's name; one this build cannot
    /// name reads as the fallback figure.
    public static readonly CrestChargeKind Heraldic = new(Kinds.Heraldic, "heraldic", "Heraldry", true, true, normalize: charge => charge,
        read: (kind, text, _) => new(kind, CrestSymbol.Named(text) ?? CrestSymbol.Fallback),
        write: charge => (charge.Symbol?.Name, null));
    public static readonly CrestChargeKind System = new(Kinds.System, "system", "SF Symbol", true, true, normalize: charge =>
        Trimmed(charge) is { Length: > 0 } text ? charge with { Text = text } : Undrawn(),
        read: (kind, text, _) => new(kind, Text: text), write: charge => (charge.Text ?? "", null));
    public static readonly CrestChargeKind Emoji = new(Kinds.Emoji, "emoji", "Emoji", false, false, normalize: charge =>
        string.IsNullOrEmpty(charge.Text) ? Undrawn()
            : charge with { Text = new global::System.Globalization.StringInfo(charge.Text).SubstringByTextElements(0, 1) },
        read: (kind, text, _) => new(kind, Text: text), write: charge => (charge.Text ?? "", null));
    /// A monogram, stored with its letters and its style, serif unless it says.
    public static readonly CrestChargeKind Monogram = new(Kinds.Monogram, "monogram", "Monogram", true, true, normalize: charge =>
        Trimmed(charge) is { Length: > 0 } text
            ? charge with { Text = FirstTextElements(text.ToUpperInvariant(), MaximumMonogramLength).ToUpperInvariant() }
            : Undrawn(),
        read: (kind, text, style) => new(kind, Text: text, Style: CrestMonogramStyle.Named(style) ?? CrestMonogramStyle.Serif),
        write: charge => (charge.Text ?? "", (charge.Style ?? CrestMonogramStyle.Serif).Name));
    public static readonly CrestChargeKind None = new(Kinds.None, "none", "None", false, false, normalize: charge => charge,
        read: (kind, _, _) => new(kind), write: _ => (null, null));

    public static IReadOnlyList<CrestChargeKind> All { get; } = [Heraldic, System, Emoji, Monogram, None];

    #endregion

    #region Variables

    public Kinds Kind { get; }
    public string Name { get; }

    /// The choice's name where a person picks it.
    [Localized]
    public string Title { get; }

    /// Whether the figure is painted in the crest's emblem color; an emoji keeps its own colors.
    public bool IsTinted { get; }

    /// Whether the figure is drawn in a stroke weight a person can choose.
    public bool TakesWeight { get; }

    /// A figure of this kind as the renderer draws it.
    private readonly Func<CrestCharge, CrestCharge> normalize;

    /// A figure of this kind as stored, from its stored value and style.
    private readonly Func<CrestChargeKind, string, string?, CrestCharge> read;

    /// What a figure of this kind stores: its value and its style, each
    /// left out when null.
    private readonly Func<CrestCharge, (string? Value, string? Style)> write;

    #endregion

    #region Constructors

    private CrestChargeKind(Kinds kind, string name, string title, bool isTinted, bool takesWeight,
        Func<CrestCharge, CrestCharge> normalize, Func<CrestChargeKind, string, string?, CrestCharge> read,
        Func<CrestCharge, (string? Value, string? Style)> write) {
        Kind = kind;
        Name = name;
        Title = title;
        IsTinted = isTinted;
        TakesWeight = takesWeight;
        this.normalize = normalize;
        this.read = read;
        this.write = write;
    }

    #endregion

    #region Actions - Lookup

    public static CrestChargeKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion

    #region Actions - Figures

    /// `charge`, a figure of this kind, as the renderer draws it: names and
    /// letters trimmed, one emoji, a monogram of at most two capitals, and
    /// nothing drawn in place of an empty one.
    public CrestCharge Normalized(CrestCharge charge) => normalize(charge);

    /// The figure of this kind a stored `value` and `style` hold.
    internal CrestCharge Read(string value, string? style) => read(this, value, style);

    /// What `charge`, a figure of this kind, stores: its value and its style.
    internal (string? Value, string? Style) Written(CrestCharge charge) => write(charge);

    /// No figure, drawn in place of an empty one.
    private static CrestCharge Undrawn() => new(None);

    private static string Trimmed(CrestCharge charge) => charge.Text?.Trim() ?? "";

    private static string FirstTextElements(string text, int count) {
        var elements = new global::System.Globalization.StringInfo(text);
        return elements.LengthInTextElements <= count ? text : elements.SubstringByTextElements(0, count);
    }

    #endregion
}

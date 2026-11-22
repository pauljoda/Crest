using System.Globalization;

using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The name, symbol, accent and look an imported or drafted Space takes. A
/// blank name reads as `UntitledName` and a blank symbol as the default one;
/// the look is kept within the ranges every device draws.
public sealed record SpaceCustomization(string Name, string Symbol, SpaceAccent Accent, SpaceBranding Branding) {
    #region Static Variables

    /// What a Space named with nothing but blanks is called.
    public const string UntitledName = "Untitled Space";

    /// The longest name a Space takes, named or imported.
    public const int MaximumNameLength = 200;

    /// The symbol a Space given a blank one wears.
    private const string DefaultSymbol = "square.grid.2x2";

    #endregion

    #region Actions - Names

    /// `name` with the next number none of the `taken` names wears: "Work"
    /// and "Work 2" both give "Work 2" while no name is that, else "Work 3",
    /// and on. Names compare trimmed and in any letter case, and a long name
    /// gives up its end so the numbered one fits in `MaximumNameLength`.
    internal static string NextName(string name, IEnumerable<string> taken) {
        ArgumentNullException.ThrowIfNull(name);
        var trimmed = name.TrimEnd();
        var gap = trimmed.LastIndexOf(' ');
        var stem = gap > 0 && int.TryParse(trimmed.AsSpan(gap + 1), out _) ? trimmed[..gap] : trimmed;
        var names = taken.Select(candidate => candidate.Trim()).ToHashSet(StringComparer.CurrentCultureIgnoreCase);
        var number = 2;
        while (names.Contains(Numbered(stem, number))) number++;
        return Numbered(stem, number);
    }

    /// `stem` and then `number`, the stem cut at a whole character so the name
    /// fits in `MaximumNameLength`, and trimmed as names compare, so a stem
    /// with no room left gives the number alone.
    private static string Numbered(string stem, int number) {
        var suffix = $" {number}";
        var room = MaximumNameLength - suffix.Length;
        if (stem.Length > room) {
            var end = 0;
            var characters = StringInfo.GetTextElementEnumerator(stem);
            while (characters.MoveNext() && characters.ElementIndex + characters.GetTextElement().Length <= room)
                end = characters.ElementIndex + characters.GetTextElement().Length;
            stem = stem[..end].TrimEnd();
        }
        return (stem + suffix).TrimStart();
    }

    /// The name `name` gives a Space: trimmed, or `UntitledName` when blank.
    public static string Resolved(string name) => string.IsNullOrWhiteSpace(name) ? UntitledName : name.Trim();

    /// The name a person gave a Space, trimmed, as `Resolved` reads it. Throws
    /// `Rejected` with `InvalidName` for one longer than a Space name holds.
    internal static string Chosen(string name) {
        var resolved = Resolved(name);
        if (resolved.Length > MaximumNameLength)
            throw new Rejected(new InvalidName(MaximumNameLength));
        return resolved;
    }

    /// The symbol `symbol` gives a Space: trimmed, or the default one when blank.
    internal static string ResolvedSymbol(string symbol) => string.IsNullOrWhiteSpace(symbol) ? DefaultSymbol : symbol.Trim();

    #endregion
}

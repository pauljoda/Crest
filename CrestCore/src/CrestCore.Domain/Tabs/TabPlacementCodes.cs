using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Stable placement spellings in native session and sync records.
public static class TabPlacementCodes {
    #region Variables

    public const string Current = "current";
    public const string Pinned = "pinned";
    public const string Saved = "saved";

    #endregion

    #region Actions - Decoding

    public static TabPlacement? Parse(string? value) => value switch {
        Current => TabPlacement.Current,
        Pinned => TabPlacement.Pinned,
        Saved => TabPlacement.Saved,
        _ => null
    };

    #endregion

    #region Actions - Encoding

    public static string Name(TabPlacement placement) => placement switch {
        TabPlacement.Current => Current,
        TabPlacement.Pinned => Pinned,
        TabPlacement.Saved => Saved,
        _ => throw new BrowserRuleException(BrowserRuleCodes.InvalidPlacement)
    };

    #endregion
}

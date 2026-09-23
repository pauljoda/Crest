namespace CrestCore.Domain;

/// Which icon a tab shows, and when an observed favicon may take that slot.
/// The image bytes never reach this layer: a tab's icon is a stored mode, a
/// symbol and the address the cached image was pulled from, and those three
/// decide everything. Emoji text normalization stays with the platform that
/// owns grapheme handling; this owns the stored vocabulary and the precedence.
public static class TabIconPolicy {
    #region Variables

    /// One storage slot holds either an SF Symbol name or an emoji, so the
    /// emoji spelling carries a prefix that makes the two unambiguous.
    public const string EmojiPrefix = "crest.emoji:";
    public const string WebSymbol = "globe";

    #endregion

    #region Actions - Icon precedence

    /// A stored mode wins. A tab written before modes were stored — or one whose
    /// stored term this build cannot name — takes its mode from its own symbol,
    /// so an unfamiliar term never pins a tab to a mode it did not choose.
    public static TabIconMode Mode(TabIconMode? storedMode, string? symbol)
        => storedMode ?? (symbol is { } value && value.StartsWith(EmojiPrefix, StringComparison.Ordinal)
            && value.Length > EmojiPrefix.Length ? TabIconMode.Emoji : TabIconMode.Automatic);

    public static string Symbol(string? emoji) {
        var trimmed = emoji?.Trim();
        if (string.IsNullOrEmpty(trimmed)) throw new BrowserRuleException(BrowserRuleCodes.InvalidTabIcon);
        return trimmed.StartsWith(EmojiPrefix, StringComparison.Ordinal) ? trimmed : EmojiPrefix + trimmed;
    }

    /// An edit must name a mode this build knows; an absent or unknown term is refused.
    public static TabIconMode RequireMode(TabIconMode? value)
        => value ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidTabIcon);

    #endregion
}

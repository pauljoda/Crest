namespace CrestCore.Contracts;

/// <summary>
/// What a person chose for a split: its name, icon and tint, each with the time it
/// last changed so devices merge the fields independently. Membership stays on the
/// tabs, whose <see cref="TabState.SplitGroupId"/> names this group.
/// </summary>
public sealed record SplitGroupState(
    Guid Id,
    string? CustomTitle = null,
    DateTimeOffset? TitleModifiedAt = null,
    string? CustomIconSymbol = null,
    DateTimeOffset? IconModifiedAt = null,
    BrandColor? Tint = null,
    DateTimeOffset? TintModifiedAt = null) {
    #region Static Variables

    /// The fewest tabs of one split a sidebar or a window shows as a split. A shorter
    /// run keeps its membership, so a staggered sync can bring the rest, and shows as
    /// plain tabs until it does.
    public const int MinimumShownMembers = 2;

    #endregion

    #region Variables

    /// The title a split shows while no one has named it.
    [Localized]
    public string DefaultTitle => "Split View";

    public string DefaultTitleComment => "The title of a split view no one has named.";

    /// <summary>The title a person gave the split, trimmed, or null for a split that shows
    /// <see cref="DefaultTitle"/>. A blank title, however it arrived, is none.</summary>
    [Resolved]
    public string? DisplayTitle => string.IsNullOrWhiteSpace(CustomTitle) ? null : CustomTitle.Trim();

    /// <summary>The emoji the split shows as its icon, or null when it shows none.</summary>
    [Resolved]
    public string? DisplayEmojiIcon => EmojiIcon.Parse(CustomIconSymbol)?.Emoji;

    #endregion
}

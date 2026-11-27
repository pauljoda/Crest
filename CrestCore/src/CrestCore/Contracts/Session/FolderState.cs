using System.Text;

using CrestCore.Domain;

namespace CrestCore.Contracts;

/// <summary>
/// A folder in a Space's saved or open section. Folders form a forest through
/// <see cref="ParentId"/>, and a child always shares its parent's <see cref="Location"/>.
/// <see cref="Symbol"/> and <see cref="Color"/> are null until someone chooses them.
/// <see cref="OrderAnchorTabId"/> is the tab an empty folder keeps its place before.
/// <see cref="IsGroup"/> marks a group: a single-level folder of open tabs that
/// holds no folders and sits in no folder. A folder of the open tabs, a group
/// among them, goes when its last tab leaves it; a saved folder stays empty.
/// <see cref="MadeByTidy"/> marks a group Tidy made, which a later Tidy fills
/// with the open tabs of the same topic rather than making another; it syncs
/// with the group, and counts only while the folder is a group.
/// </summary>
[Observed]
public sealed record FolderState(
    Guid Id,
    TabPlacement Location,
    string Title,
    string? Symbol = null,
    BrandColor? Color = null,
    Guid? ParentId = null,
    bool IsCollapsed = false,
    DateTimeOffset? CollapseModifiedAt = null,
    Guid? OrderAnchorTabId = null,
    bool IsGroup = false,
    bool MadeByTidy = false) {
    #region Static Variables

    /// The most folders deep a folder may nest, counting the folder itself.
    public const int MaximumDepth = 16;

    /// The SF Symbol a folder shows until someone chooses one.
    public const string DefaultSymbol = "folder";

    /// What a folder without a title is called, wherever it comes from.
    public const string UntitledTitle = "Untitled Folder";

    /// The longest title a folder takes, renamed or imported.
    public const int MaximumTitleLength = 500;

    /// The color a folder the core makes for a person's tabs is drawn in, and the one
    /// a folder shows until someone chooses one.
    public static BrandColor DefaultColor { get; } = new(0.43, 0.48, 0.54);

    #endregion

    #region Variables

    /// The symbol the folder shows: the one chosen, or <see cref="DefaultSymbol"/>.
    [Resolved]
    public string DisplaySymbol => Symbol ?? DefaultSymbol;

    /// The color the folder is drawn in: the one chosen, or <see cref="DefaultColor"/>.
    [Resolved]
    public BrandColor DisplayColor => Color ?? DefaultColor;

    /// Whether the folder goes when its last tab leaves it: a folder of the
    /// open tabs does, and a saved folder stays empty.
    internal bool GoesWhenEmptied => !Location.IsDurable;

    /// Whether collapsing every folder closes this one: an open folder, at
    /// any depth. A group keeps its own state.
    internal bool CollapsesWithAll => !IsGroup && !IsCollapsed;

    /// Whether Tidy files the open tabs of a topic named `matchKey` into this
    /// folder: a group Tidy made, at the top level of the open tabs, whose
    /// title matches.
    internal bool TakesTidyTopic(string matchKey) => MadeByTidy && IsGroup && FolderTree.PlacesGroup(Location, ParentId)
        && matchKey.Length > 0 && MatchKey(Title) == matchKey;

    #endregion

    #region Actions - Matching

    /// The key an imported folder, or a topic Tidy names, matches an existing
    /// one by: its letters and digits in compatibility form, lowercased.
    internal static string MatchKey(string title) => string.Concat(title.Normalize(NormalizationForm.FormKD)
        .Where(char.IsLetterOrDigit)).ToLowerInvariant();

    #endregion
}

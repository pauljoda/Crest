namespace CrestCore.Contracts;

/// <summary>
/// A folder in a Space's saved or open section. Folders form a forest through
/// <see cref="ParentId"/>, and a child always shares its parent's <see cref="Location"/>.
/// <see cref="Symbol"/> and <see cref="Color"/> are null until someone chooses them.
/// <see cref="OrderAnchorTabId"/> is the tab an empty folder keeps its place before.
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
    Guid? OrderAnchorTabId = null) {
    #region Static Variables

    /// The color a folder the core makes for a person's tabs is drawn in.
    public static BrandColor DefaultColor { get; } = new(0.43, 0.48, 0.54);

    #endregion
}

namespace CrestCore.Contracts;

/// <summary>
/// A tab as its Space keeps it. A native view has <see cref="NativeContent"/> and no
/// <see cref="Url"/>; a Start Page has neither. <see cref="StoredIconMode"/> is null
/// for a tab that never chose how its icon is filled, which then follows its
/// <see cref="Symbol"/>. Favicon bytes, live pages and engine history are never part of it.
/// </summary>
public sealed record TabState(
    Guid Id,
    string Title,
    string? Url,
    NativeTabContent? NativeContent,
    string? SavedUrl,
    string Symbol,
    string? FaviconUrl,
    TabIconAccent? IconAccent,
    TabIconMode? StoredIconMode,
    TabPlacement Placement,
    Guid? FolderId,
    Guid? SplitGroupId,
    DateTimeOffset LastActivatedAt,
    DateTimeOffset? PositionModifiedAt,
    string? CustomTitle,
    DateTimeOffset? TitleModifiedAt,
    bool KeepsPageLoaded);

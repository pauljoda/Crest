namespace CrestCore.Domain;

// Durable values deliberately omit native pages, presentation leases, and engine history stacks.
public sealed record TabState(Guid Id, TabContent Content, string? Url, string Title,
    TabPlacement Placement, Guid? FolderId, string? SavedUrl, string? CustomTitle,
    DateTimeOffset LastActivatedAt, DateTimeOffset? PositionModifiedAt, DateTimeOffset? TitleModifiedAt,
    bool KeepsPageLoaded, Guid? SplitGroupId);

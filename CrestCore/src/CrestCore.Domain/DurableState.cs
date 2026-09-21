namespace CrestCore.Domain;

// Durable values deliberately omit native pages, presentation leases, and engine history stacks.
public sealed record TabState(TabId Id, TabContent Content, string? Url, string Title,
    TabPlacement Placement, FolderId? FolderId, string? SavedUrl, string? CustomTitle,
    DateTimeOffset LastActivatedAt, DateTimeOffset? PositionModifiedAt, DateTimeOffset? TitleModifiedAt,
    bool KeepsPageLoaded, Guid? SplitGroupId);
public sealed record FolderState(FolderId Id, string Name, TabPlacement Location,
    FolderId? ParentId, bool IsCollapsed, DateTimeOffset? CollapseModifiedAt = null, TabId? OrderAnchorTabId = null);
public sealed record ArchiveState(TabState Tab, DateTimeOffset ClosedAt, string Reason);
public sealed record SpaceState(SpaceId Id, ProfileId ProfileId, string Name, bool RequiresAuthentication,
    IReadOnlyList<TabState> Tabs, IReadOnlyList<FolderState> Folders,
    IReadOnlyList<ArchiveState> Archive, IReadOnlyList<HistoryVisit> History, TabId? SelectedTabId,
    SearchPreferences? Search = null, bool SupportsDeviceAuthentication = true, RetentionPreferences? Retention = null, ContentBlockingPolicy ContentBlocking = ContentBlockingPolicy.Balanced);
public sealed record WindowState(WindowId Id, SpaceId SpaceId, IReadOnlyDictionary<SpaceId, TabId?> Selections,
    string? PlatformSceneId = null);
public sealed record WorkspaceState(WorkspaceId Id, SpaceId? DefaultSpaceId, SpaceId? SelectedSpaceId,
    IReadOnlyList<SpaceState> Spaces, IReadOnlyList<WindowState> Windows,
    IReadOnlyList<SpaceDeletionState>? SpaceDeletions = null);
public sealed record SpaceDeletionState(SpaceId Space, ProfileId Profile, DateTimeOffset RequestedAt, bool Completed = false);

namespace CrestCore.Contracts;

/// Whether a tab dragged out of a window may leave it for a window of its
/// own. `DraggedTabs` is the multi-selection the drag carries, or null when
/// it carries the one tab.
public sealed record CanTearOff(Guid WindowId, Guid SpaceId, Guid ProfileId, Guid TabId, IReadOnlyList<Guid>? DraggedTabs)
    : Query<TearOffPermission>;

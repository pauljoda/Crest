namespace CrestCore.Domain;

/// The repaired selection of a window: its Space, one tab choice per Space in
/// the order the facts were supplied, the split layouts it may keep, and the
/// Spaces it now records as captured (null for a window that predates capture).
public sealed record WindowRepair(Guid SelectedSpaceId, IReadOnlyList<WindowTabSelection> Selections,
    IReadOnlyList<Guid> SplitLayouts, IReadOnlyList<Guid>? CapturedSpaceIds);

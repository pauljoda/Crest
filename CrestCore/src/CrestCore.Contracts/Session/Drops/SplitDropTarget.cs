namespace CrestCore.Contracts;

/// The cards a window shows, the split of `TabId`, the tab it shows, and the
/// rule that refuses a lift joining them, or null when it may.
public sealed record SplitDropTarget(Guid TabId, Rejection? Refusal);

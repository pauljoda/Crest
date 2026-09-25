namespace CrestCore.Contracts;

/// Where each numbered command leads when the window shows `TabCount` tabs in
/// sidebar order and the device has `SpaceCount` Spaces.
public sealed record NumberedSelections(int TabCount, int SpaceCount) : Query<NumberedSelectionList>;

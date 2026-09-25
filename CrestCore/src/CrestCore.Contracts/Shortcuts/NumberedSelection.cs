namespace CrestCore.Contracts;

/// A numbered command, what it selects from, and where it leads: the Space
/// `SpaceId`, and for a tab the tab `TabId` the window shows there.
public sealed record NumberedSelection(ShortcutCommand Command, NumberedSelectionTarget Target, Guid SpaceId, Guid? TabId);

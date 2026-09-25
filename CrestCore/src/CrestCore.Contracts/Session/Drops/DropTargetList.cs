namespace CrestCore.Contracts;

/// Where a lift may drop. `Refusal` is the rule that refuses the lift itself,
/// such as `SelectionChanged` or `PinnedTabsDragAlone`, which leaves every list
/// empty. Otherwise `Lists` holds every list of the Space's sidebar, sections
/// first and then each folder's inside, dropped into at its end; `Spaces` every
/// other Space the window may show; `Split` the cards the window shows, or null
/// when it shows no tab; and `FolderAroundTabIds` the open tabs a new folder
/// may be made around, in sidebar order.
public sealed record DropTargetList(Rejection? Refusal, IReadOnlyList<ListDropTarget> Lists, IReadOnlyList<SpaceDropTarget> Spaces,
    SplitDropTarget? Split, IReadOnlyList<Guid> FolderAroundTabIds);

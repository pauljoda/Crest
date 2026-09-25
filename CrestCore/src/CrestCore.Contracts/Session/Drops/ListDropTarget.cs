namespace CrestCore.Contracts;

/// One list of a Space's sidebar a lift may drop into, the inside of
/// `FolderId` or the top level of `Section`, and the rule that refuses the
/// drop, or null when it may land there.
public sealed record ListDropTarget(TabPlacement Section, Guid? FolderId, Rejection? Refusal);

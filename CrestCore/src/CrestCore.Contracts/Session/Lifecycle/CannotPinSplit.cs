namespace CrestCore.Contracts;

/// The tab is in a split, and the section it would move to holds no splits,
/// so it moves only by leaving its split.
public sealed record CannotPinSplit(Guid TabId) : Rejection;

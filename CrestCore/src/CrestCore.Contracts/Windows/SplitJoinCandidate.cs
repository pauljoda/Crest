namespace CrestCore.Contracts;

/// The tab "Split With Next Tab" adds to the split of the tab a window shows:
/// the first tab row after the row that holds it, in the same list of its
/// Space's sidebar (its section's top level, or its folder's inside), whose tab
/// is in no split, when the core would join it; or none.
public sealed record SplitJoinCandidate(Guid WindowId) : Query<SplitJoinCandidateTab>;

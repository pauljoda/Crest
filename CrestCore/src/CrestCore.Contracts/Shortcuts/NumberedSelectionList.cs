namespace CrestCore.Contracts;

/// Each numbered command that reaches something, in catalog order.
public sealed record NumberedSelectionList(IReadOnlyList<NumberedSelection> Selections);

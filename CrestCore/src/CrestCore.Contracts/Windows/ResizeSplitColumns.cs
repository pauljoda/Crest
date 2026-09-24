namespace CrestCore.Contracts;

/// Records the share of the width each column of a split group takes in one
/// window. Shares that drift from summing to one are normalized; a list that
/// cannot describe columns is refused with `InvalidSplitColumnShares`.
public sealed record ResizeSplitColumns(Guid WindowId, Guid GroupId, IReadOnlyList<double> Shares) : WindowIntent;

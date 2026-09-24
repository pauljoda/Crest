namespace CrestCore.Contracts;

/// The shares cannot describe a split's columns: none, more than a split may
/// hold, or one that is not a finite share greater than zero and at most the
/// whole width.
public sealed record InvalidSplitColumnShares : Rejection;

namespace CrestCore.Domain;

/// One numbered command and the zero-based position it selects, or null when
/// there is nothing at that position.
public sealed record NumberedSelection(string Command, NumberedSelectionTarget Target, int? Index);

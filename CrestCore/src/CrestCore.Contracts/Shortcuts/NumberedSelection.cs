namespace CrestCore.Contracts;

/// A numbered command, what it selects from, and the zero-based position it selects there.
public sealed record NumberedSelection(ShortcutCommand Command, NumberedSelectionTarget Target, int Index);

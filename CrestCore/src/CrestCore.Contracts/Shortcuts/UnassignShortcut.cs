namespace CrestCore.Contracts;

/// Leaves `Command` without a chord.
public sealed record UnassignShortcut(ShortcutCommand Command) : ShortcutIntent;

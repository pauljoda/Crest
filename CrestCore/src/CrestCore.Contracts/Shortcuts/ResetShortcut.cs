namespace CrestCore.Contracts;

/// Forgets the person's choice for `Command`, which answers to its default
/// again. Nothing else loses its chord.
public sealed record ResetShortcut(ShortcutCommand Command) : ShortcutIntent;

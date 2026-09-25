namespace CrestCore.Contracts;

/// Binds `Keys` to `Command`, taking them from every other offered command
/// that answers to them, which is left without a chord.
public sealed record ReassignShortcut(ShortcutCommand Command, KeyCombination Keys) : ShortcutIntent;

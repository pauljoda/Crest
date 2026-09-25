namespace CrestCore.Contracts;

/// Forgets every shortcut choice, including those for commands this device
/// does not offer.
public sealed record ResetShortcuts() : ShortcutIntent;

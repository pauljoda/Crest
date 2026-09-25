namespace CrestCore.Contracts;

/// Binds `Keys` to `Command`. Refused while another offered command answers to
/// them, so nothing loses its chord until the person confirms with
/// `ReassignShortcut`.
public sealed record AssignShortcut(ShortcutCommand Command, KeyCombination Keys) : ShortcutIntent;

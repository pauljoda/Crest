namespace CrestCore.Contracts;

/// The keys one command answers to now, or null when it has none, and whether
/// they are the person's choice rather than the default.
public sealed record ShortcutBinding(ShortcutCommand Command, KeyCombination? Keys, bool IsCustomized);

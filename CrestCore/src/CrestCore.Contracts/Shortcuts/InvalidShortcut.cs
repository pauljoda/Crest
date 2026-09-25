namespace CrestCore.Contracts;

/// The keys can never be a shortcut: they hold no supported modifier, so a
/// plain key would never reach the focused text field, or they name no key.
public sealed record InvalidShortcut(KeyCombination Keys) : Rejection;

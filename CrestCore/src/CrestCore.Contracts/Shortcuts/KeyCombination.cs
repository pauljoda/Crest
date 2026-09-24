namespace CrestCore.Contracts;

/// A key and the modifiers held with it, as the shortcut catalog writes a
/// default. `Key` is the character the key types, or a special key's native
/// spelling, such as `leftArrow`, when `IsSpecialKey`.
public sealed record KeyCombination(string Key, bool IsSpecialKey, ShortcutModifiers Modifiers);

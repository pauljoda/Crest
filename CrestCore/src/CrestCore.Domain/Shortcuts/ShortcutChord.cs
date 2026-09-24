using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// One key chord: a typed character or a named special key, and a modifier
/// mask. The mask keeps every bit the platform stored so equality matches the
/// native value exactly; only the four supported bits make a chord usable.
public sealed record ShortcutChord {
    #region Variables

    public const int Command = (int)ShortcutModifiers.Command;
    public const int Option = (int)ShortcutModifiers.Option;
    public const int Control = (int)ShortcutModifiers.Control;
    public const int Shift = (int)ShortcutModifiers.Shift;
    public const int SupportedModifiers = Command | Option | Control | Shift;
    public const int MaximumCharacterLength = 64;

    public string Key { get; }
    public bool IsSpecial { get; }
    public int Modifiers { get; }

    /// A chord needs at least one supported modifier, so a plain key keeps
    /// reaching the focused text field.
    public bool IsValid => (Modifiers & SupportedModifiers) != 0;

    #endregion

    #region Initialization

    private ShortcutChord(string key, bool isSpecial, int modifiers) {
        Key = key;
        IsSpecial = isSpecial;
        Modifiers = modifiers;
    }

    #endregion

    #region Actions - Construction

    /// A typed character, compared in canonical composition so the two
    /// spellings of an accented key are one chord.
    public static ShortcutChord Character(string character, int modifiers) {
        ArgumentNullException.ThrowIfNull(character);
        if (character.Length == 0 || character.Length > MaximumCharacterLength)
            throw new BrowserRuleException(BrowserRuleCodes.InvalidShortcut);
        return new(character.Normalize(NormalizationForm.FormC), false, modifiers);
    }

    /// The chord a catalog default names.
    public static ShortcutChord Of(KeyCombination keys) {
        ArgumentNullException.ThrowIfNull(keys);
        return keys.IsSpecialKey ? Special(keys.Key, (int)keys.Modifiers) : Character(keys.Key, (int)keys.Modifiers);
    }

    public static ShortcutChord Special(string key, int modifiers) {
        ArgumentNullException.ThrowIfNull(key);
        if (ShortcutSpecialKey.Named(key) is null) throw new BrowserRuleException(BrowserRuleCodes.InvalidShortcut);
        return new(key, true, modifiers);
    }

    #endregion
}

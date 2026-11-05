using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The person's shortcut choices on this device: for each command's stored
/// name, the chord they gave it, or null when they left it without one, and
/// who answers its keys while a focused page uses them too. A choice for a
/// command this build does not know is carried through, and one equal to the
/// command's default is never kept.
///
/// `offered` is the ordered set of commands this device shows anywhere; only
/// they can hold or lose a chord. A default that yields to overrides never
/// takes a chord the person gave another offered command; resetting that
/// command restores it. Values are immutable: every change answers a new one.
public sealed class ShortcutOverrides {
    #region Static Variables

    public const int MaximumOverrides = 256;
    public const int MaximumCommandLength = 64;

    public static readonly ShortcutOverrides None = new(new SortedDictionary<string, ShortcutChord?>(StringComparer.Ordinal),
        new SortedDictionary<string, ShortcutPreference>(StringComparer.Ordinal));

    #endregion

    #region Variables

    private readonly SortedDictionary<string, ShortcutChord?> chords;
    private readonly SortedDictionary<string, ShortcutPreference> preferences;

    /// Every chord choice, by command name in ordinal order.
    public IEnumerable<KeyValuePair<string, ShortcutChord?>> Chords => chords;

    /// Every preference choice, by command name in ordinal order.
    public IEnumerable<KeyValuePair<string, ShortcutPreference>> Preferences => preferences;

    /// Whether the person changed any shortcut, including one this device does not offer.
    public bool IsCustomized => chords.Count > 0 || preferences.Count > 0;

    #endregion

    #region Constructors

    private ShortcutOverrides(SortedDictionary<string, ShortcutChord?> chords, SortedDictionary<string, ShortcutPreference> preferences) {
        this.chords = chords;
        this.preferences = preferences;
    }

    /// The choices `stored` and `preferred` name, the first for each command
    /// name, leaving out names no command could have and anything past the
    /// limit.
    public static ShortcutOverrides Restore(IEnumerable<KeyValuePair<string, ShortcutChord?>> stored,
        IEnumerable<KeyValuePair<string, ShortcutPreference>>? preferred = null) {
        ArgumentNullException.ThrowIfNull(stored);
        return new(Kept(stored), Kept(preferred ?? []));
    }

    private static SortedDictionary<string, T> Kept<T>(IEnumerable<KeyValuePair<string, T>> stored) {
        var kept = new SortedDictionary<string, T>(StringComparer.Ordinal);
        foreach (var (command, choice) in stored) {
            if (kept.Count >= MaximumOverrides) break;
            if (command.Length is 0 or > MaximumCommandLength) continue;
            kept.TryAdd(command, choice);
        }
        return kept;
    }

    #endregion

    #region Actions - Resolution

    /// Each offered command's chord and preference now, in `offered` order.
    public IReadOnlyList<ShortcutBinding> Bindings(IReadOnlyList<ShortcutCommand> offered, DevicePlatform platform) =>
        [.. offered.Select(command => Binding(command, Effective(command, offered, platform)))];

    /// A command bound to text editing keys leaves them to the page and the
    /// field, whatever it prefers, so it has no preference to choose.
    private ShortcutBinding Binding(ShortcutCommand command, ShortcutChord? chord) {
        bool editsText = chord?.EditsText == true;
        bool chooses = !command.IsReservedFromPages && !editsText;
        var preference = editsText ? ShortcutPreference.PreferWebsite
            : chooses ? preferences.GetValueOrDefault(command.Name) ?? command.DefaultPreference : command.DefaultPreference;
        return new(command, chord?.Keys, chords.ContainsKey(command.Name) || preferences.ContainsKey(command.Name), preference, chooses,
            editsText);
    }

    /// The chord `command` answers to now.
    public ShortcutChord? Effective(ShortcutCommand command, IReadOnlyList<ShortcutCommand> offered, DevicePlatform platform) {
        ArgumentNullException.ThrowIfNull(command);
        ArgumentNullException.ThrowIfNull(offered);
        if (chords.TryGetValue(command.Name, out var custom)) return custom;
        if (command.DefaultShortcut(platform) is not { } fallback) return null;
        var chord = ShortcutChord.Of(fallback.Keys);
        if (fallback.YieldsToOverrides && offered.Any(other => chords.TryGetValue(other.Name, out var taken) && taken == chord)) return null;
        return chord;
    }

    /// The other offered commands that answer to `chord` now.
    public IReadOnlyList<ShortcutCommand> Holders(ShortcutChord chord, ShortcutCommand command, IReadOnlyList<ShortcutCommand> offered,
        DevicePlatform platform) =>
        [.. offered.Where(other => other != command && Effective(other, offered, platform) == chord)];

    #endregion

    #region Actions - Changes

    /// `command` answering to `chord`. Throws `Rejected` with `ShortcutInUse`
    /// naming every other offered command that answers to it.
    public ShortcutOverrides Assigning(ShortcutCommand command, ShortcutChord chord, IReadOnlyList<ShortcutCommand> offered,
        DevicePlatform platform) {
        var holders = Holders(chord, command, offered, platform);
        if (holders.Count > 0) throw new Rejected(new ShortcutInUse(holders));
        return Setting(command, chord, platform);
    }

    /// `command` answering to `chord`, which every other offered command that
    /// answered to it gives up.
    public ShortcutOverrides Reassigning(ShortcutCommand command, ShortcutChord chord, IReadOnlyList<ShortcutCommand> offered,
        DevicePlatform platform) {
        var revised = this;
        foreach (var holder in Holders(chord, command, offered, platform)) revised = revised.Setting(holder, null, platform);
        return revised.Setting(command, chord, platform);
    }

    /// `command` answering to no chord.
    public ShortcutOverrides Unassigning(ShortcutCommand command, DevicePlatform platform) => Setting(command, null, platform);

    /// `command` back on its default.
    public ShortcutOverrides Resetting(ShortcutCommand command) {
        ArgumentNullException.ThrowIfNull(command);
        if (!chords.ContainsKey(command.Name) && !preferences.ContainsKey(command.Name)) return this;
        var revised = new SortedDictionary<string, ShortcutChord?>(chords, StringComparer.Ordinal);
        var preferred = new SortedDictionary<string, ShortcutPreference>(preferences, StringComparer.Ordinal);
        revised.Remove(command.Name);
        preferred.Remove(command.Name);
        return new(revised, preferred);
    }

    /// `preference` answering `command`'s keys while a focused page uses them
    /// too; one equal to its default is no choice at all. A command reserved
    /// from pages keeps its own.
    public ShortcutOverrides Preferring(ShortcutCommand command, ShortcutPreference preference) {
        ArgumentNullException.ThrowIfNull(command);
        ArgumentNullException.ThrowIfNull(preference);
        if (command.IsReservedFromPages) return this;
        var preferred = new SortedDictionary<string, ShortcutPreference>(preferences, StringComparer.Ordinal);
        if (preference == command.DefaultPreference) preferred.Remove(command.Name);
        else preferred[command.Name] = preference;
        return new(chords, preferred);
    }

    /// The choices with `chord` for `command`; one equal to its default is
    /// no choice at all.
    private ShortcutOverrides Setting(ShortcutCommand command, ShortcutChord? chord, DevicePlatform platform) {
        ArgumentNullException.ThrowIfNull(command);
        ArgumentNullException.ThrowIfNull(platform);
        var fallback = command.DefaultShortcut(platform) is { } keys ? ShortcutChord.Of(keys.Keys) : null;
        var revised = new SortedDictionary<string, ShortcutChord?>(chords, StringComparer.Ordinal);
        if (chord == fallback) revised.Remove(command.Name);
        else revised[command.Name] = chord;
        return new(revised, preferences);
    }

    #endregion

    #region Actions - Equality

    /// Whether `other` holds the same choices.
    public bool SameAs(ShortcutOverrides? other) =>
        other is not null && chords.Count == other.chords.Count && preferences.Count == other.preferences.Count
        && chords.All(entry => other.chords.TryGetValue(entry.Key, out var chord) && chord == entry.Value)
        && preferences.All(entry => other.preferences.TryGetValue(entry.Key, out var preference) && preference == entry.Value);

    #endregion
}

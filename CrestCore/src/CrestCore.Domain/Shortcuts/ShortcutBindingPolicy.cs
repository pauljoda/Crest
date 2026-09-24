using CrestCore.Contracts;

namespace CrestCore.Domain;

/// How the person's overrides combine with the catalog, and what binding a
/// chord does to the commands that already hold it.
///
/// `offered` is the ordered set of commands this process shows anywhere; only
/// they can claim or lose a chord. Overrides map a command to its custom chord,
/// or to null when the person left it unassigned. Overrides for commands this
/// build does not know are carried through unchanged.
public static class ShortcutBindingPolicy {
    #region Variables

    public const int MaximumCommands = 128;
    public const int MaximumOverrides = 256;

    #endregion

    #region Actions - Resolution

    public static IReadOnlyList<ShortcutBinding> Resolve(IReadOnlyList<string> offered,
        IReadOnlyDictionary<string, ShortcutChord?> overrides, DevicePlatform platform) {
        Validate(offered, overrides);
        return offered.Select(command => new ShortcutBinding(command, Effective(command, offered, overrides, platform),
            ShortcutCatalog.Default(command, platform), overrides.ContainsKey(command))).ToArray();
    }

    /// The chord a command answers to right now. On the Mac the two new-window
    /// defaults never take a chord the person already gave another command;
    /// that override is kept, and resetting it restores the default.
    public static ShortcutChord? Effective(string command, IReadOnlyList<string> offered,
        IReadOnlyDictionary<string, ShortcutChord?> overrides, DevicePlatform platform) {
        ArgumentNullException.ThrowIfNull(command);
        ArgumentNullException.ThrowIfNull(offered);
        ArgumentNullException.ThrowIfNull(overrides);
        if (overrides.TryGetValue(command, out var custom)) return custom;
        if (ShortcutCatalog.Default(command, platform) is not { } chord) return null;
        if (platform == DevicePlatform.Desktop
            && command is ShortcutCatalog.NewBlankWindow or ShortcutCatalog.NewQuickWindow
            && offered.Any(other => overrides.TryGetValue(other, out var taken) && taken == chord)) return null;
        return chord;
    }

    #endregion

    #region Actions - Assignment

    /// Binds `chord` to `command`, or clears the command when `chord` is null.
    /// Every other offered command holding the chord is a conflict; conflicts
    /// block the binding until the person confirms replacing them, and then
    /// lose their chord. A value equal to the default is stored as no override.
    public static ShortcutAssignment Assign(string command, ShortcutChord? chord, bool replacingConflicts,
        IReadOnlyList<string> offered, IReadOnlyDictionary<string, ShortcutChord?> overrides, DevicePlatform platform) {
        ArgumentNullException.ThrowIfNull(command);
        Validate(offered, overrides);
        if (chord is { IsValid: false }) return new(ShortcutAssignmentResult.Invalid, [], null);
        string[] conflicts = chord is null ? [] : offered
            .Where(other => other != command && Effective(other, offered, overrides, platform) == chord).ToArray();
        if (conflicts.Length > 0 && !replacingConflicts) return new(ShortcutAssignmentResult.Conflict, conflicts, null);
        var revised = new Dictionary<string, ShortcutChord?>(overrides, StringComparer.Ordinal);
        foreach (var conflict in conflicts) Set(revised, conflict, null, platform);
        Set(revised, command, chord, platform);
        return new(ShortcutAssignmentResult.Assigned, conflicts, revised);
    }

    private static void Set(Dictionary<string, ShortcutChord?> overrides, string command, ShortcutChord? chord,
        DevicePlatform platform) {
        if (chord == ShortcutCatalog.Default(command, platform)) overrides.Remove(command);
        else overrides[command] = chord;
    }

    private static void Validate(IReadOnlyList<string> offered, IReadOnlyDictionary<string, ShortcutChord?> overrides) {
        ArgumentNullException.ThrowIfNull(offered);
        ArgumentNullException.ThrowIfNull(overrides);
        if (offered.Count > MaximumCommands || overrides.Count > MaximumOverrides)
            throw new BrowserRuleException(BrowserRuleCodes.ShortcutCommandLimit);
        if (offered.Distinct(StringComparer.Ordinal).Count() != offered.Count)
            throw new BrowserRuleException(BrowserRuleCodes.DuplicateShortcutCommand);
    }

    #endregion
}

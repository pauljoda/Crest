namespace CrestCore.Domain;

/// The outcome of binding a chord. `Overrides` is the complete revised
/// override set, present only when the assignment was applied.
public sealed record ShortcutAssignment(ShortcutAssignmentResult Result, IReadOnlyList<string> Conflicts,
    IReadOnlyDictionary<string, ShortcutChord?>? Overrides);

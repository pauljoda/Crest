namespace CrestCore.Domain;

/// Whether a chord was bound, is already held by other commands, or can never
/// be a shortcut. The shortcut policy spells a result as its `Name`.
public sealed class ShortcutAssignmentResult {
    #region Variables

    public static readonly ShortcutAssignmentResult Assigned = new(name: "assigned");
    public static readonly ShortcutAssignmentResult Conflict = new(name: "conflict");
    public static readonly ShortcutAssignmentResult Invalid = new(name: "invalid");

    public static IReadOnlyList<ShortcutAssignmentResult> All { get; } = [Assigned, Conflict, Invalid];

    public string Name { get; }

    #endregion

    #region Constructors

    private ShortcutAssignmentResult(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static ShortcutAssignmentResult? Named(string? name) => All.FirstOrDefault(result => result.Name == name);

    #endregion
}

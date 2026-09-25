namespace CrestCore.Contracts;

/// Other offered commands answer to the keys already.
public sealed record ShortcutInUse(IReadOnlyList<ShortcutCommand> Commands) : Rejection;

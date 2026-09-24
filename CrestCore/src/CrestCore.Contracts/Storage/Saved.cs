namespace CrestCore.Contracts;

/// Everything the core handed its session file up to file revision `Revision`
/// is on disk: the stored session's edits and this device's saved windows.
public sealed record Saved(long Revision) : Change;

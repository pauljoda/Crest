namespace CrestCore.Contracts;

/// Every edit the stored session accepted up to `Revision` is on disk.
public sealed record Saved(long Revision) : Change;

namespace CrestCore.Contracts;

/// A save the core started on its own failed. The accepted session stays in
/// memory, and the next save writes everything that is not yet on disk.
public sealed record StorageFailed(StorageFailure Reason) : Change;

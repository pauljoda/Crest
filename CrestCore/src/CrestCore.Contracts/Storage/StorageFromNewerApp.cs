namespace CrestCore.Contracts;

/// The stored session or its sync journal was written by a newer version of
/// the app, which this build must not overwrite.
public sealed record StorageFromNewerApp : Rejection;

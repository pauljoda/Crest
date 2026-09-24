namespace CrestCore.Contracts;

/// How the host creates the core. `StorageDirectory` is where the core keeps
/// `session.sqlite`; null keeps everything in memory, as private browsing,
/// temporary workspaces, tests and previews need.
public sealed record AppConfiguration(string? StorageDirectory) : Configuration;

namespace CrestCore.Domain;

/// One Space's download retention for the profile it uses. A null lifetime
/// keeps records forever.
public readonly record struct DownloadRetentionLimit(Guid Profile, double? Lifetime);

namespace CrestCore.Contracts;

/// One Space's download retention for the profile it uses. A null lifetime
/// keeps records forever.
public sealed record DownloadRetention(Guid ProfileId, TimeSpan? Lifetime);

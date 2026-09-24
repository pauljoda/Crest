namespace CrestCore.Contracts;

/// The lowercased host without a leading `www.`, or null when the preference is
/// off or the address has no host.
public sealed record QuickWindowSiteKey(string? Site);

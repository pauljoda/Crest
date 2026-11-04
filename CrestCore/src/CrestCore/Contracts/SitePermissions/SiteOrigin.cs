using System.Net;

namespace CrestCore.Contracts;

/// The scheme, host and port a site permission belongs to. Scheme and host
/// compare case-insensitively, so both are lowercased, and an unspecified web
/// port is the scheme's default; other schemes keep the port they were given.
/// Every origin is normalized as it is made, so two spellings of one origin
/// are equal. The permission rules refuse an origin that is not `IsValid`.
[NormalizedOnConstruction]
public sealed record SiteOrigin(string Scheme, string Host, int Port) {
    #region Static Variables

    public const int MaximumSchemeLength = 64;
    public const int MaximumHostLength = 1_024;

    #endregion

    #region Variables

    public string Scheme { get; } = Scheme.ToLowerInvariant();

    public string Host { get; } = Host.ToLowerInvariant();

    public int Port { get; } = Port > 0 ? Port : WebScheme.Named(Scheme.ToLowerInvariant())?.DefaultPort ?? Port;

    /// A scheme and a host of usable length, and a port that is a port or
    /// unspecified.
    public bool IsValid => Scheme.Length is > 0 and <= MaximumSchemeLength && Host.Length is > 0 and <= MaximumHostLength
        && Port is >= -1 and <= 65_535;

    /// The origin as a person reads it: the port only when it is not the default.
    public string DisplayName => WebScheme.Named(Scheme)?.DefaultPort == Port ? $"{Scheme}://{Host}" : $"{Scheme}://{Host}:{Port}";

    /// Powerful features (location, hosted web notifications) need a secure
    /// context: HTTPS, or plain HTTP only on this device's own host. An origin
    /// the rules cannot read is never secure.
    internal bool IsSecureContext => IsValid && WebScheme.Named(Scheme) is { } scheme && (scheme.IsSecure || IsLoopback);

    /// Whether the host is this device's own: `localhost` or a name under it,
    /// or a loopback address (127.0.0.0/8 or ::1), so traffic to it never
    /// leaves the device.
    internal bool IsLoopback => Host == "localhost" || Host.EndsWith(".localhost", StringComparison.Ordinal)
        || IPAddress.TryParse(Host.Trim('[', ']'), out var address) && IPAddress.IsLoopback(address);

    #endregion
}

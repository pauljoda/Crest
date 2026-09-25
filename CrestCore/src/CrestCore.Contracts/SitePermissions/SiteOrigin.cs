namespace CrestCore.Contracts;

/// The scheme, host and port a site permission belongs to. Scheme and host
/// compare case-insensitively, so both are lowercased, and an unspecified web
/// port is the scheme's default; other schemes keep the port they were given.
/// Every origin is normalized as it is made, so two spellings of one origin
/// are equal. The permission rules refuse an origin that is not `IsValid`.
public sealed record SiteOrigin(string Scheme, string Host, int Port) {
    #region Static Variables

    public const int MaximumSchemeLength = 64;
    public const int MaximumHostLength = 1_024;

    #endregion

    #region Variables

    public string Scheme { get; } = Scheme.ToLowerInvariant();

    public string Host { get; } = Host.ToLowerInvariant();

    public int Port { get; } = Port > 0 ? Port : DefaultPort(Scheme.ToLowerInvariant()) ?? Port;

    /// A scheme and a host of usable length, and a port that is a port or
    /// unspecified.
    public bool IsValid => Scheme.Length is > 0 and <= MaximumSchemeLength && Host.Length is > 0 and <= MaximumHostLength
        && Port is >= -1 and <= 65_535;

    /// The origin as a person reads it: the port only when it is not the default.
    public string DisplayName => DefaultPort(Scheme) == Port ? $"{Scheme}://{Host}" : $"{Scheme}://{Host}:{Port}";

    #endregion

    #region Actions - Ports

    /// The port a web scheme uses when none is given, or null for any other scheme.
    private static int? DefaultPort(string scheme) => scheme switch {
        "http" => 80,
        "https" => 443,
        _ => null
    };

    #endregion
}

namespace CrestCore.Domain;

/// The scheme, host and port a permission belongs to. Scheme and host compare
/// case-insensitively, so both are lowercased, and an unspecified web port is
/// the scheme's default. Other schemes keep the port they were given.
public sealed record SiteOrigin {
    #region Variables

    public const int MaximumSchemeLength = 64;
    public const int MaximumHostLength = 1_024;

    public string Scheme { get; }
    public string Host { get; }
    public int Port { get; }

    /// The origin as a person reads it: the port only when it is not the default.
    public string DisplayName => IsDefaultPort ? $"{Scheme}://{Host}" : $"{Scheme}://{Host}:{Port}";

    private bool IsDefaultPort => (Scheme == "http" && Port == 80) || (Scheme == "https" && Port == 443);

    #endregion

    #region Constructors

    public SiteOrigin(string scheme, string host, int port) {
        if (string.IsNullOrEmpty(scheme) || scheme.Length > MaximumSchemeLength || string.IsNullOrEmpty(host)
            || host.Length > MaximumHostLength || port is < -1 or > 65_535)
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSiteOrigin);
        Scheme = scheme.ToLowerInvariant();
        Host = host.ToLowerInvariant();
        Port = port > 0 ? port : Scheme switch {
            "http" => 80,
            "https" => 443,
            _ => port
        };
    }

    #endregion
}

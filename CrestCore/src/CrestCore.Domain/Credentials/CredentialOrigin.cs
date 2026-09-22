namespace CrestCore.Domain;

/// The canonical HTTP(S) origin a credential belongs to. The platform
/// canonicalizes scheme, host and default port before it reaches the core, so
/// equality is exact member equality.
public sealed record CredentialOrigin {
    #region Variables

    public const int MaximumHostLength = 1_024;

    public string Scheme { get; }
    public string Host { get; }
    public int Port { get; }

    public bool IsSecure => Scheme == "https";

    #endregion

    #region Constructors

    public CredentialOrigin(string scheme, string host, int port) {
        if (scheme is not ("https" or "http") || string.IsNullOrEmpty(host) || host.Length > MaximumHostLength
            || port is < 1 or > 65_535) throw new BrowserRuleException(BrowserRuleCodes.InvalidCredentialOrigin);
        Scheme = scheme;
        Host = host;
        Port = port;
    }

    #endregion
}

namespace CrestCore.Contracts;

/// The canonical HTTP(S) origin a credential belongs to. The platform
/// canonicalizes scheme, host and default port before it reaches the core, so
/// equality is exact member equality. The credential rules refuse an origin
/// that is not `IsValid`.
public sealed record CredentialOrigin(string Scheme, string Host, int Port) {
    #region Variables

    public const int MaximumHostLength = 1_024;

    public bool IsValid => Scheme is "https" or "http" && !string.IsNullOrEmpty(Host) && Host.Length <= MaximumHostLength
        && Port is >= 1 and <= 65_535;

    public bool IsSecure => Scheme == "https";

    #endregion
}

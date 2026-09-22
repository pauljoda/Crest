namespace CrestCore.Domain;

/// HTTP authentication rules: which challenges Crest prompts for, how the
/// prompt names the server asking, and the trust override reserved for the
/// physical-validation fixture build.
public static class AuthenticationPolicy {
    #region Variables

    public const int MaximumCredentialAttempts = 3;
    public const string PhysicalValidationBundleIdentifier = "com.pauldavis.crest.physical-validation";

    #endregion

    #region Actions - Challenges

    /// Proxy and non-HTTP challenges keep the system's handling. Basic and
    /// Digest prompt until the server has refused three attempts, then cancel.
    public static AuthenticationHandling Handling(AuthenticationMethod method, bool isProxy, int previousFailureCount) {
        if (isProxy || method == AuthenticationMethod.Other) return AuthenticationHandling.PerformDefaultHandling;
        return previousFailureCount < MaximumCredentialAttempts
            ? AuthenticationHandling.PromptForCredentials : AuthenticationHandling.Cancel;
    }

    /// The server as the prompt names it: the host, with the port only when it
    /// is not the scheme's default. Null when the challenge has no host; the
    /// platform then names Crest itself.
    public static string? SourceLabel(string host, int port, string? scheme) {
        ArgumentNullException.ThrowIfNull(host);
        if (host.Length == 0) return null;
        bool isDefault = scheme?.ToLowerInvariant() switch {
            "http" => port == 80,
            "https" => port == 443,
            _ => false
        };
        return isDefault ? host : $"{host}:{port}";
    }

    #endregion

    #region Actions - Fixture trust

    /// Only the physical-validation build may trust a server certificate, and
    /// only the one whose SHA-256 fingerprint it was built with.
    public static bool TrustsPhysicalValidationServer(string? bundleIdentifier, string? expectedCertificateSha256,
        string actualCertificateSha256) {
        ArgumentNullException.ThrowIfNull(actualCertificateSha256);
        return bundleIdentifier == PhysicalValidationBundleIdentifier && expectedCertificateSha256 is { } expected
            && IsSha256(expected) && IsSha256(actualCertificateSha256)
            && string.Equals(expected, actualCertificateSha256, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsSha256(string value) => value.Length == 64 && value.All(char.IsAsciiHexDigit);

    #endregion
}
